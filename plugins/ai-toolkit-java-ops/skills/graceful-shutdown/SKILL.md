---
name: graceful-shutdown
description: >
  Java / Spring Boot graceful shutdown — drain in-flight requests, async work, consumers and clients on Kubernetes pod
  termination. Use when a new service is created or a rolling update shows 5xx spikes.
tier: must
applies_to: [rest, event, scheduler, monolith]
depends_on: []
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Graceful Shutdown Skill
A pod terminating mid-request is the single most common cause of "flaky 5xx
during deploys". This skill removes that class of bug.

## 1. Enable Spring Boot graceful shutdown

```yaml
server:
  shutdown: graceful
spring:
  lifecycle:
    timeout-per-shutdown-phase: 30s
```

Spring stops accepting new HTTP requests, lets in-flight ones complete (up
to the timeout), then closes the connector.

`server.shutdown: graceful` is the default since Spring Boot 3.4; keep it explicit so the intent is visible and a
`server.shutdown: immediate` in a profile stands out. `timeout-per-shutdown-phase` applies to **each** lifecycle phase
that has to wait (the web server is one phase, message-listener containers are others), not to the whole shutdown.

## 2. Kubernetes contract

```yaml
spec:
  terminationGracePeriodSeconds: 60        # > Spring's timeout + ingress drain
  containers:
    - name: app
      lifecycle:
        preStop:
          sleep:
            seconds: 5                      # let kube-proxy / ingress remove the endpoint (native sleep, k8s ≥ 1.30)
```

On clusters older than 1.30 use `exec: { command: ["sh","-c","sleep 5"] }` instead (needs `sh` in the image).

Timing:
1. K8s marks the Pod Terminating and starts removing it from the Service endpoints.
2. The `preStop` hook runs (`sleep 5`) and gives the ingress / kube-proxy time to update.
3. Only then does K8s send `SIGTERM`; Spring's graceful shutdown kicks in (up to 30 s).
4. K8s sends `SIGKILL` once `terminationGracePeriodSeconds` has elapsed — the clock started at step 1, so it covers preStop **and** the drain.

**Budget.** Everything after step 1 must fit in the grace period, and the steps run one after another:

```
terminationGracePeriodSeconds  >  preStop
                                + timeout-per-shutdown-phase × (number of phases that actually wait:
                                                                 web server, Kafka/Rabbit containers, …)
                                + executor awaitTerminationSeconds (bean destruction runs after the phases)
```

Example: HTTP only → 5 + 30 + 20 = 55 s < 60 s. HTTP + a Kafka listener → 5 + 30 + 30 + 20 = 85 s, so either raise
`terminationGracePeriodSeconds` to 90 or lower the timeouts. If the budget is exceeded, `SIGKILL` lands mid-work.

## 3. Async work / `TaskExecutor`

Every named `TaskExecutor` (see `spring-boot-conventions` §7) must:

```java
ex.setWaitForTasksToCompleteOnShutdown(true);
ex.setAwaitTerminationSeconds(20);
```

…and any hand-rolled `ExecutorService` follows the canonical pattern:
`@PreDestroy` → `shutdown()` → `awaitTermination(...)` → `shutdownNow()` if timeout.

Boot's auto-configured `applicationTaskExecutor` (used when you define no `Executor` bean of your own — defining one
switches it off) drains with:

```yaml
spring:
  task:
    execution:
      shutdown:
        await-termination: true
        await-termination-period: 20s
```

With virtual threads (`spring.threads.virtual.enabled: true`) the auto-configured executor is a
`SimpleAsyncTaskExecutor` (a thread per task, no queue); it only waits for running tasks if its
`taskTerminationTimeout` is set — verify your Boot version maps the `shutdown.*` properties onto it, or keep long
`@Async` work on a named, bounded `ThreadPoolTaskExecutor` with the settings above. Pick the rejection policy per use case
(`spring-boot-conventions` §7): `CallerRunsPolicy` runs the task on the calling (HTTP) thread, which is back-pressure
for batch work but adds latency to requests.

## 4. Message consumers

There is **no** `spring.kafka.listener.shutdown-timeout` or `spring.rabbitmq.listener.*.shutdown-timeout` property.
The containers stop in their lifecycle phase (bounded by `spring.lifecycle.timeout-per-shutdown-phase`); set the
container's own shutdown timeout in code when the default is too short:

```java
@Bean   // Boot applies it to the auto-configured Kafka listener container factory
ContainerCustomizer<Object, Object, ConcurrentMessageListenerContainer<Object, Object>> kafkaShutdownTimeout() {
    return container -> container.getContainerProperties().setShutdownTimeout(20_000L);   // default 10 s
}

@Bean   // Boot applies it to the auto-configured SimpleRabbitListenerContainerFactory
ContainerCustomizer<SimpleMessageListenerContainer> rabbitShutdownTimeout() {
    return container -> container.setShutdownTimeout(20_000L);   // default 5 s
}
```

- **Kafka**: the container finishes processing the **current poll batch** (not just one record) and then stops.
  Whether the offsets of that batch are committed depends on the ack mode (`BATCH`/`RECORD` commit on stop;
  `MANUAL` commits only what the listener acknowledged). `spring.kafka.listener.immediate-stop: true` stops after the
  current record instead of the whole batch.
- **RabbitMQ**: the container stops consuming, waits up to its shutdown timeout for in-flight deliveries, and
  unacknowledged messages are requeued by the broker.
- For long-running consumers, periodically check
  `Thread.currentThread().isInterrupted()` so a shutdown can cancel work.

## 5. Outbound HTTP clients

- `WebClient` / `RestClient` connection pools close automatically with the
  Spring context. No action needed if the bean is registered with Spring.
- For native HTTP clients (Apache HttpClient), wire a `@PreDestroy` that
  calls `client.close()`.

## 6. Database

- The connection pool (HikariCP) closes on context shutdown.
- Open transactions are rolled back. Long-running transactions are an
  anti-pattern (`@Transactional` must complete within a few seconds).

## 7. Health probes during shutdown

K8s removes a Terminating pod from the Service endpoints **because it is terminating** (step 1 above), not because a
probe failed — that is why the `preStop` sleep exists. On `SIGTERM` Spring closes the context and sets readiness to
`REFUSING_TRAFFIC` (`OUT_OF_SERVICE` on `/actuator/health/readiness`) whether or not graceful shutdown is enabled; it is
a second line of defence for anything that still routes by readiness. **Liveness** stays `UP` so K8s doesn't restart
the pod mid-drain.

## Component test — settings, readiness and an in-flight request

Guild rule #17 asks for this test. It uses the service's **own** configuration (no property overrides), checks the
settings, then closes the context (the same path `SIGTERM` takes) and asserts that readiness went to
`REFUSING_TRAFFIC` and that a request already in flight still completes:

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import(GracefulShutdownComponentTest.SlowTestController.class)
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_EACH_TEST_METHOD)   // two tests close the context
class GracefulShutdownComponentTest {

    @LocalServerPort private int port;
    @Value("${server.servlet.context-path:}") private String contextPath;
    @Autowired private ConfigurableApplicationContext context;
    @Autowired private ApplicationAvailability availability;
    @Autowired private Environment environment;

    @RestController
    static class SlowTestController {
        @GetMapping("/test/slow")
        String slow() throws InterruptedException {
            Thread.sleep(2_000);   // simulates a request that is in flight when shutdown starts
            return "done";
        }
    }

    @Test
    void config_shutdownSettings_areGracefulWithPhaseTimeout() {
        assertThat(environment.getProperty("server.shutdown", "graceful")).isEqualTo("graceful");  // 3.4+ default
        assertThat(environment.getProperty("spring.lifecycle.timeout-per-shutdown-phase")).isNotBlank();
    }

    @Test
    void close_readiness_becomesRefusingTraffic() {
        assertThat(availability.getReadinessState()).isEqualTo(ReadinessState.ACCEPTING_TRAFFIC);

        context.close();     // what SIGTERM triggers

        assertThat(availability.getReadinessState()).isEqualTo(ReadinessState.REFUSING_TRAFFIC);
    }

    @Test
    void close_inFlightRequest_completesWith200() throws Exception {
        final HttpClient client = HttpClient.newHttpClient();
        final HttpRequest request = HttpRequest.newBuilder(
                URI.create("http://localhost:" + port + contextPath + "/test/slow")).build();
        final CompletableFuture<HttpResponse<String>> inFlight =
                client.sendAsync(request, HttpResponse.BodyHandlers.ofString());
        Thread.sleep(500);   // let the request reach the controller

        context.close();     // what SIGTERM triggers

        final HttpResponse<String> response = inFlight.get(10, TimeUnit.SECONDS);
        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.body()).isEqualTo("done");
    }
}
```

If the service secures every path, permit `/test/**` in the component-test security configuration or send a test
token. Keep it in the component-test suite (it takes a few seconds).

## Smoke test (load test during rolling update)

In addition to the component test above:

Run `k6` / `vegeta` at 50 rps for 60 s while triggering
`kubectl rollout restart deploy/foo`. Expected outcome: zero `5xx`, zero
connection resets. Add as a nightly job.

## Do / Don't

✅ `server.shutdown=graceful` is non-negotiable.
✅ `terminationGracePeriodSeconds > preStop + timeout-per-shutdown-phase × waiting phases + executor waits` (§2 budget).
✅ Every executor is configured to wait for tasks on shutdown.
❌ Never `System.exit(...)` from application code.
❌ Never set `terminationGracePeriodSeconds: 0`.
❌ Never assume HTTP idempotency saves you — non-idempotent `POST`s lost
mid-shutdown still corrupt user state.


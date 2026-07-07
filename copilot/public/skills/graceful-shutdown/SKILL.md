---
name: graceful-shutdown
description: Wire graceful shutdown into a Spring Boot service so Kubernetes pod terminations drain in-flight requests, async work, message consumers, and outbound clients without dropped requests or stuck transactions. Use whenever a new service is created or when a deployment shows 5xx spikes during rolling updates.
tier: must
applies_to: [rest, event, scheduler, monolith]
depends_on: []
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Graceful Shutdown Skill (public)

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

## 2. Kubernetes contract

```yaml
spec:
  terminationGracePeriodSeconds: 60        # > Spring's timeout + ingress drain
  containers:
    - name: app
      lifecycle:
        preStop:
          exec:
            command: ["sh","-c","sleep 5"]  # let kube-proxy / ingress remove the endpoint
```

Timing:
1. K8s sends `SIGTERM` and removes the Pod from the Service endpoints.
2. `preStop sleep 5` gives the ingress / kube-proxy time to update.
3. Spring's graceful shutdown kicks in (30 s).
4. K8s sends `SIGKILL` after `terminationGracePeriodSeconds`.

Always `terminationGracePeriodSeconds > timeout-per-shutdown-phase + preStop`.

## 3. Async work / `TaskExecutor`

Every named `TaskExecutor` (see `spring-boot-conventions` §7) must:

```java
ex.setWaitForTasksToCompleteOnShutdown(true);
ex.setAwaitTerminationSeconds(20);
```

…and any hand-rolled `ExecutorService` follows the canonical pattern from
`code-structure` §4e: `@PreDestroy` → `shutdown()` →
`awaitTermination(...)` → `shutdownNow()` if timeout.

## 4. Message consumers

- **Kafka**: `spring.kafka.listener.shutdown-timeout: 20s`. The container
  finishes the in-flight record and commits its offset before exit.
- **RabbitMQ**: `spring.rabbitmq.listener.simple.shutdown-timeout: 20s`.
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

Spring sets `readiness` to `OUT_OF_SERVICE` as soon as `SIGTERM` is
received → the readiness probe fails → K8s removes the pod from the
Service. This is automatic when `server.shutdown=graceful`. **Liveness**
stays `UP` so K8s doesn't restart the pod mid-drain.

## Smoke test (load test during rolling update)

Run `k6` / `vegeta` at 50 rps for 60 s while triggering
`kubectl rollout restart deploy/foo`. Expected outcome: zero `5xx`, zero
connection resets. Add as a nightly job.

## Do / Don't

✅ `server.shutdown=graceful` is non-negotiable.
✅ `terminationGracePeriodSeconds > timeout-per-shutdown-phase + preStop`.
✅ Every executor is configured to wait for tasks on shutdown.
❌ Never `System.exit(...)` from application code.
❌ Never set `terminationGracePeriodSeconds: 0`.
❌ Never assume HTTP idempotency saves you — non-idempotent `POST`s lost
mid-shutdown still corrupt user state.


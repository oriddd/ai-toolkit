---
name: health-indicator
description: >
  Java / Spring Boot Actuator readiness HealthIndicator for a downstream dependency, wired into the readiness group
  and Helm chart; asks for name, URL, endpoint, status and interval. Use when adding a readiness check for a
  downstream dependency.
tier: should
applies_to: [rest, event, scheduler, monolith]
depends_on: [cd, observability]
ships_templates: true
hitl: true
version: 1.0
last_reviewed: 2026-06-28
---

# Health Indicator Skill (HITL)

Adds a new **readiness** `HealthIndicator` to a microservice so that
the Kubernetes readiness probe (`/actuator/health/readiness`) only reports
`UP` when the downstream dependency is reachable.

The skill follows the pattern proven in this repo:
- `health/indicator/AbstractReadinessIndicator` – reusable base (HTTP call, timeout, result cache).
- `health/indicator/<Dep>HealthIndicator` – per-dependency concrete class.
- `health/config/ReadinessClientConfig` – shared `RestClient` with short timeouts.
- `health/config/<Dep>ReadinessProperties` – typed `@ConfigurationProperties` record (`spring-boot-conventions`).
- `application.yaml` – `management.endpoint.health.group.readiness.include`
  registers the indicator name.

## Phase 1 – Interview the developer

Ask **each** question, confirm before writing files. Use sensible defaults
but always show them.

| # | Question | Stored as | Default |
| - | -------- | --------- | ------- |
| 1 | Human-readable name of the dependency (e.g. `Foo-Dependency`)? | `dependencyDisplayName` | — |
| 2 | Indicator bean key (camelCase, e.g. `fooDependency`)? | `indicatorBeanName` | derived from #1 |
| 3 | Base URL env var name (e.g. `FOO_DEPENDENCY_HOST` + `PORT` → assembled in `application.yaml`)? | `baseUrlEnv` | derived |
| 4 | Base URL local default (e.g. `http://localhost:8080/my-dependency/api`)? | `baseUrlDefault` | — |
| 5 | Readiness endpoint path (e.g. `/1.0/actuator/api-healthcheck/readiness`)? | `readinessEndpoint` | `/actuator/health/readiness` |
| 6 | Expected HTTP status code that means "ready" (default `200`)? | `successStatusCode` | `200` |
| 7 | Probe interval in seconds (how long a result is cached, default `30`)? | `cacheSeconds` | `30` |
| 8 | Should failure cause the pod to be removed from the Service (i.e. block `readiness`)? | `includeInReadiness` | `yes` |
| 9 | Is auth required to call the endpoint? (`none` / `bearer` / `basic`) | `authMode` | `none` |
| 10 | Kubernetes Service name and port of the dependency (for the Helm env vars)? | `k8sServiceName`, `k8sServicePort` | — |

Derive the remaining placeholders — show them in the echo-back so the developer can correct them:

| Placeholder | Derivation | Example |
| --- | --- | --- |
| `Dep` | PascalCase of `indicatorBeanName` | `FooDependency` |
| `configKey` | kebab-case of `indicatorBeanName` (the YAML prefix) | `foo-dependency` |
| `baseUrlEnvHost` / `baseUrlEnvPort` | `baseUrlEnv` + `_HOST` / `_PORT` | `FOO_DEPENDENCY_HOST` |
| `baseUrlPath` | path part of `baseUrlDefault` (empty if none) | `/my-dependency/api` |
| `basePackage` / `basePackagePath` | the service's root package, from the main `@SpringBootApplication` class | `com.example.foo` / `com/example/foo` |
| `appPort`, `contextPath` | `server.port` / `server.servlet.context-path` in `application.yaml` | `8080`, `/my-service` |

Run this interview in the main session: a subagent cannot ask the developer, so it returns the open questions and
its assumed defaults to the caller instead.

After collecting answers, **echo them back** and require explicit confirmation
before generating files.

## Phase 2 – Files to generate / modify

### a) `health/indicator/AbstractReadinessIndicator.java`
Create it **only if it does not already exist**. Place it under
`src/main/java/{{basePackagePath}}/health/indicator/AbstractReadinessIndicator.java`.
It must:
- Implement `HealthIndicator` (`org.springframework.boot.actuate.health.HealthIndicator`; Boot 4 moves it to
  `org.springframework.boot.health.contributor`).
- Accept a `RestClient` and the cache TTL (`Duration`) via constructor. `RestClient` is part of `spring-web`, so a
  servlet service needs no extra starter. (A reactive WebFlux service may use `WebClient` with the same contract.)
- Define `protected abstract` getters: `getServiceName()`, `getSuccessStatusCode()`,
  `getReadinessURI()` — the subclasses override them as `protected` (package-private overrides of a `protected`
  method don't compile).
- Rely on the client's connect/read timeouts (about 2 s, set in `ReadinessClientConfig`) — a hung dependency must not
  hang the probe.
- **Cache the last result for `cacheSeconds`** (an `AtomicReference` holding the `Health` and its timestamp): the
  readiness probe calls the indicator every `periodSeconds`, and Actuator's
  `management.endpoint.health.cache.time-to-live` does not cover the probe group paths.
- Catch `RestClientException` and any `Exception` → return `Health.down()`.
- Log at `debug` on every refresh; `error` on failure.

### b) `health/config/ReadinessClientConfig.java`
Create if missing. Single `@Bean RestClient readinessRestClient(RestClient.Builder builder)` built from Boot's
injected `RestClient.Builder` (keeps observation/tracing), with short timeouts:

```java
@Bean
RestClient readinessRestClient(final RestClient.Builder builder) {
    final SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
    requestFactory.setConnectTimeout(Duration.ofSeconds(2));
    requestFactory.setReadTimeout(Duration.ofSeconds(2));
    return builder.requestFactory(requestFactory).build();
}
```

If `authMode != none`, add the appropriate default header / interceptor
(e.g. `defaultHeader(HttpHeaders.AUTHORIZATION, ...)`).

### b2) `health/config/<Dep>ReadinessProperties.java`

```java
@Validated
@ConfigurationProperties(prefix = "{{configKey}}")
public record {{Dep}}ReadinessProperties(
        @NotBlank String baseUrl,
        @NotBlank String readinessEndpoint,
        @DefaultValue("{{cacheSeconds}}s") Duration cacheTtl) {
}
```

Registered by `@ConfigurationPropertiesScan` on the application class (`spring-boot-conventions`).

### c) `health/indicator/<Dep>HealthIndicator.java`
Use [`templates/HealthIndicator.java.tmpl`](./templates/HealthIndicator.java.tmpl):

```java
@Component("{{indicatorBeanName}}")
public class {{Dep}}HealthIndicator extends AbstractReadinessIndicator {
    private static final String SERVICE_NAME = "{{dependencyDisplayName}}";
    private final {{Dep}}ReadinessProperties properties;

    public {{Dep}}HealthIndicator(final RestClient readinessRestClient,
                                  final {{Dep}}ReadinessProperties properties) {
        super(readinessRestClient, properties.cacheTtl());
        this.properties = properties;
    }

    @Override protected String getServiceName()    { return SERVICE_NAME; }
    @Override protected int getSuccessStatusCode() { return {{successStatusCode}}; }
    @Override protected String getReadinessURI()   { return properties.baseUrl() + properties.readinessEndpoint(); }
}
```

The Spring bean name (`@Component("fooDependency")`) is **the key** used
by the readiness group in `application.yaml`. Keep them in sync.

### d) `application.yaml` (main)

```yaml
management:
  endpoints.web.exposure.include: prometheus,health,info   # see note below — merge, don't overwrite
  endpoint:
    prometheus.access: unrestricted   # Boot 3.4+: replaces the deprecated prometheus.enabled
    health:
      access: unrestricted            # Boot 3.4+: replaces the deprecated health.enabled
      probes.enabled: true
      group:
        readiness:
          include:
            - readinessState
            - {{indicatorBeanName}}     # ← add this line

{{configKey}}:
  base-url: http://${{{baseUrlEnvHost}}:localhost}:${{{baseUrlEnvPort}}:8080}{{baseUrlPath}}
  readiness-endpoint: {{readinessEndpoint}}
```

**Exposure.** Make sure `health` (and `prometheus`) are in the service's existing
`management.endpoints.web.exposure.include`; add to the list, never replace it. `httpexchanges` (Boot 3's
replacement for `httptrace`, needs an `HttpExchangeRepository` bean) exposes request headers — include it only when
the ingress denies `/actuator/**` from outside (`cd`).

If the dependency already exists in `application.yaml`, only **append** the
`readiness-endpoint` line and the `group.readiness.include` entry; do not
duplicate.

### e) `application.yaml` (test)
Set deterministic values so component tests do not perform real HTTP calls
(or are stubbed by a `WireMock` server or a test double):

```yaml
{{configKey}}:
  base-url: http://host:port/path
  readiness-endpoint: /readiness
```

### f) Helm chart – `templates/deployment.yaml`
Append env vars under `env:`:

```yaml
- name: {{baseUrlEnvHost}}
  value: "{{k8sServiceName}}"
- name: {{baseUrlEnvPort}}
  value: "{{k8sServicePort}}"
```

Ask the developer for `{{k8sServiceName}}` and `{{k8sServicePort}}` if not
provided in Phase 1.

### g) Unit test – `<Dep>HealthIndicatorTest`
Generate alongside, using the `unit-tests` skill, asserting:
- `health()` returns `UP` when the `RestClient` returns the expected status (stub it with `MockRestServiceServer`
  bound to a `RestClient.Builder`).
- Returns `DOWN` on non-matching status, `RestClientException`, or arbitrary
  `RuntimeException`.
- A second `health()` call inside `cacheTtl` does not call the dependency again.
- `getReadinessURI()` concatenates `baseUrl + readinessEndpoint`.

## Phase 3 – Validate

1. `mvn -q test` – unit tests pass.
2. `curl -s http://localhost:{{appPort}}{{contextPath}}/actuator/health/readiness`
   on a running instance prints both `readinessState` and
   `{{indicatorBeanName}}` entries.
3. `helm template helm-chart | grep -A1 {{baseUrlEnvHost}}` – env var present.

## Phase 4 – Hand-off summary

Print:
- File(s) created/modified.
- The exact env vars the platform team must set in the target cluster.
- That the readiness probe now **fails closed**: when the dependency is unreachable for longer than
  `failureThreshold * periodSeconds` (defaults from `cd`: 3 × 10 s = 30 s) the pod goes Unready and leaves the Service.
  A shared outage therefore takes every replica out at once — add only dependencies the service truly cannot work without.

## Do / Don't

✅ Always extend `AbstractReadinessIndicator`; never re-implement HTTP polling.
✅ Always register the indicator in the `readiness` group – otherwise the pod
will be marked Ready even when the dependency is down.
✅ Cache the result (the indicator is called on every probe – avoid hammering
the downstream). `AbstractReadinessIndicator` caches for `cacheSeconds`; Spring's
`management.endpoint.health.cache.time-to-live` does not apply to the probe group paths, so don't rely on it.
❌ Never include the indicator in the `liveness` group – a downstream outage
must not restart your pod, only de-register it from the Service.
❌ Never log secrets or full URLs with credentials.

## Templates

- [`HealthIndicator.java.tmpl`](./templates/HealthIndicator.java.tmpl) — Concrete health indicator skeleton.

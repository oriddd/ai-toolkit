---
name: health-indicator
description: Interactive (HITL) skill that adds a Spring Boot Actuator readiness HealthIndicator for a downstream dependency. Prompts the developer for the dependency name, base URL, readiness endpoint, expected success status code, and probe interval, then wires the indicator into the `readiness` health group and the Helm chart.
tier: should
applies_to: [rest, event, scheduler, monolith]
depends_on: [cd, observability]
ships_templates: true
hitl: true
version: 1.0
last_reviewed: 2026-06-28
---

# this Health Indicator Skill (HITL)

Adds a new **readiness** `HealthIndicator` to a microservice so that
the Kubernetes readiness probe (`/actuator/health/readiness`) only reports
`UP` when the downstream dependency is reachable.

The skill follows the pattern proven in this repo:
- `health/indicator/AbstractReadinessIndicator` – reusable base.
- `health/indicator/<Dep>HealthIndicator` – per-dependency concrete class.
- `health/config/ReadinessClientConfig` – shared `WebClient`.
- `application.yaml` – `management.endpoint.health.group.readiness.include`
  registers the indicator name.

## Phase 1 – Interview the developer

Ask **each** question, confirm before writing files. Use sensible defaults
but always show them.

| # | Question | Stored as | Default |
| - | -------- | --------- | ------- |
| 1 | Human-readable name of the dependency (e.g. `Foo-Dependency`)? | `serviceDisplayName` | — |
| 2 | Indicator bean key (camelCase, e.g. `fooDependency`)? | `indicatorBeanName` | derived from #1 |
| 3 | Base URL env var name (e.g. `FOO_DEPENDENCY_HOST` + `PORT` → assembled in `application.yaml`)? | `baseUrlEnv` | derived |
| 4 | Base URL local default (e.g. `http://localhost:8100/foo-dependency/api/rest`)? | `baseUrlDefault` | — |
| 5 | Readiness endpoint path (e.g. `/1.0/actuator/api-healthcheck/readiness`)? | `readinessEndpoint` | `/actuator/health/readiness` |
| 6 | Expected HTTP status code that means "ready" (default `200`)? | `successStatusCode` | `200` |
| 7 | Probe interval in seconds (cache window, default `30`)? | `cacheSeconds` | `30` |
| 8 | Should failure cause the pod to be removed from the Service (i.e. block `readiness`)? | `includeInReadiness` | `yes` |
| 9 | Is auth required to call the endpoint? (`none` / `bearer` / `basic`) | `authMode` | `none` |

After collecting answers, **echo them back** and require explicit confirmation
before generating files.

## Phase 2 – Files to generate / modify

### a) `health/indicator/AbstractReadinessIndicator.java`
Create it **only if it does not already exist**. Place it under
`src/main/java/{{basePackagePath}}/health/indicator/AbstractReadinessIndicator.java`.
It must:
- Implement `HealthIndicator` (`org.springframework.boot.actuate.health.HealthIndicator`).
- Accept a `WebClient` via constructor.
- Define `abstract` getters: `getServiceName()`, `getSuccessStatusCode()`,
  `getReadinessURI()`.
- Catch `RestClientException` and any `Exception` → return `Health.down()`.
- Log at `debug` on every refresh; `error` on failure.

### b) `health/config/ReadinessClientConfig.java`
Create if missing. Single `@Bean WebClient readinessWebClient()` built with
`WebClient.builder().build()`. If `authMode != none`, add the appropriate
default header / filter (e.g. `defaultHeader(HttpHeaders.AUTHORIZATION, ...)`).

### c) `health/indicator/<Dep>HealthIndicator.java`
Use [`templates/HealthIndicator.java.tmpl`](./templates/HealthIndicator.java.tmpl):

```java
@Component("{{indicatorBeanName}}")
public class {{Dep}}HealthIndicator extends AbstractReadinessIndicator {
    private static final String SERVICE_NAME = "{{serviceDisplayName}}";
    private final String baseUrl;
    private final String readinessEndpoint;

    @Autowired
    public {{Dep}}HealthIndicator(final WebClient readinessWebClient,
                                  @Value("${ {{configKey}}.base-url }") final String baseUrl,
                                  @Value("${ {{configKey}}.readiness-endpoint }") final String readinessEndpoint) {
        super(readinessWebClient);
        this.baseUrl = baseUrl;
        this.readinessEndpoint = readinessEndpoint;
    }

    @Override String getServiceName()          { return SERVICE_NAME; }
    @Override int getSuccessStatusCode()       { return {{successStatusCode}}; }
    @Override String getReadinessURI()         { return baseUrl + readinessEndpoint; }
}
```

The Spring bean name (`@Component("fooDependency")`) is **the key** used
by the readiness group in `application.yaml`. Keep them in sync.

### d) `application.yaml` (main)

```yaml
management:
  endpoints.web.exposure.include: prometheus,health,info,httptrace
  endpoint:
    prometheus.enabled: true
    health:
      enabled: true
      probes.enabled: true
      group:
        readiness:
          include:
            - readinessState
            - {{indicatorBeanName}}     # ← add this line

{{configKey}}:
  base-url: http://${ {{baseUrlEnvHost}} :localhost}:${ {{baseUrlEnvPort}} :8080}{{baseUrlPath}}
  readiness-endpoint: {{readinessEndpoint}}
```

If the dependency already exists in `application.yaml`, only **append** the
`readiness-endpoint` line and the `group.readiness.include` entry; do not
duplicate.

### e) `application.yaml` (test)
Set deterministic values so component tests do not perform real HTTP calls
(or are stubbed by a `WireMock`/`@MockBean`):

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
- `health()` returns `UP` when `WebClient` returns the expected status.
- Returns `DOWN` on non-matching status, `WebClientException`, or arbitrary
  `RuntimeException`.
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
- The fact that the readiness probe will now fail-open if the dependency is
  unreachable for longer than `failureThreshold * periodSeconds` (defaults
  from `cd`: 3 × 60s = 3 minutes).

## Do / Don't

✅ Always extend `AbstractReadinessIndicator`; never re-implement HTTP polling.
✅ Always register the indicator in the `readiness` group – otherwise the pod
will be marked Ready even when the dependency is down.
✅ Cache the result (the indicator is called on every probe – avoid hammering
the downstream by relying on Spring's built-in caching via
`management.endpoint.health.cache.time-to-live` if needed).
❌ Never include the indicator in the `liveness` group – a downstream outage
must not restart your pod, only de-register it from the Service.
❌ Never log secrets or full URLs with credentials.

## 5. Templates

- [`HealthIndicator.java.tmpl`](./templates/HealthIndicator.java.tmpl) — Concrete health indicator skeleton.

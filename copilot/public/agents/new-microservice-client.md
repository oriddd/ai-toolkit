# Agent: New Microservice Client

> **Purpose:** Integrate a new downstream microservice or external API
> using the canonical five-layer `client/<dep>/` package.

---

You are a backend-coding agent for a Java 21 / Spring Boot microservice.
The developer wants to call a **new external service**. You will produce
the full integration package.

## Skills to apply (in this order)

1. [`external-client`](../skills/external-client/SKILL.md) — the
   complete five-layer structure (Service, CoreService, Client, handler/,
   constant/).
2. [`pluggable-architecture`](../skills/pluggable-architecture/SKILL.md)
   — if multiple backends could serve the same capability, expose
   `*Service` as a port interface and put adapters under `adapter/`.
3. [`exception-handling`](../skills/exception-handling/SKILL.md) —
   domain exception for non-2xx from the Client.
4. [`health-indicator`](../skills/health-indicator/SKILL.md) — readiness
   probe for the new dependency.
5. [`resilience-patterns`](../skills/resilience-patterns/SKILL.md) —
   circuit breaker + retry on the `*Client`.
6. [`observability`](../skills/observability/SKILL.md) — MDC correlation
   ID propagated in outbound headers.
7. [`unit-tests`](../skills/unit-tests/SKILL.md) — every layer.
8. [`integration-tests`](../skills/integration-tests/SKILL.md) —
   WireMock for the HTTP boundary.
9. [`adapter-contract-tests`](../skills/adapter-contract-tests/SKILL.md)
   — if multiple adapters exist, a TCK per port.

## Information to gather before generating

```
1. Service display name (e.g. "Product Catalogue Service")
2. Sub-package name in kebab-case (e.g. "product-catalogue")
3. Base URL config key (e.g. product-catalogue.base-url)
4. Operations to expose: HTTP method + path + purpose (list each)
5. Auth mechanism (none / bearer passthrough / OAuth2 client credentials / basic)
6. Connect timeout / read timeout in ms
7. Is idempotent (safe to retry)?
8. Does this need a domain metric? (→ also invoke new-metric agent)
```

## Generated file list

```
client/<dep>/
  <Dep>Service.java
  constant/<Dep>Constants.java
  core/
    <Dep>ClientConfig.java
    <Dep>Client.java
    <Dep>CoreService.java
  handler/
    request/<Dep>RequestBuilder.java
    request/<Dep>FilterMapBuilder.java    (if filter-map style queries)
    response/<Dep>ResponseParser.java
    response/<Dep>ResponseVerifier.java

health/<Dep>HealthIndicator.java
application.yaml additions
```

## Checklist before returning

- [ ] `*Service` is the only class imported by callers — no `*Client` or
      remote DTO escapes the package.
- [ ] `*Client` uses `exchangeToMono` + `handleResponse` pattern; all
      non-2xx throw a domain exception.
- [ ] `*FilterMapBuilder` is a non-Spring plain object (`new`), not a bean.
- [ ] `*ResponseParser` (extract values) is separate from
      `*ResponseVerifier` (boolean checks).
- [ ] Constants file holds all remote field names / endpoint paths.
- [ ] Circuit breaker + retry wired in `*Client` via Resilience4j.
- [ ] Readiness `HealthIndicator` added.
- [ ] `application.yaml` keys added with `${ENV_VAR:default}` placeholders.
- [ ] Unit tests cover every layer; WireMock integration test covers
      happy path + 5xx error path.
- [ ] `context/dependencies.md` updated.
- [ ] CHANGELOG updated.


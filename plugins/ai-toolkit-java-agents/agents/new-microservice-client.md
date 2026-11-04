---
name: new-microservice-client
description: Integrate a new downstream microservice or external API using the canonical five-layer `client/<dep>/` package.
---

# Agent: New Microservice Client

> **Purpose:** Integrate a new downstream microservice or external API
> using the canonical five-layer `client/<dep>/` package.

---

You are a backend-coding agent for a Java 21 / Spring Boot microservice.
The developer wants to call a **new external service**. You will produce
the full integration package.

## Skills to apply (in this order)

1. `external-client` — first ask the scale questions in its §0 (how many endpoints now / in 6 months, query and response complexity) and choose
   Simple Wrapper, Lite or the full five-layer structure (Service, CoreService, Client, handler/, constant/). Default to the simplest that fits.
2. `pluggable-architecture`
   — if multiple backends could serve the same capability, expose
   `*Service` as a port interface and put adapters under `adapter/`.
3. `exception-handling` —
   domain exception for non-2xx from the Client.
4. `health-indicator` — readiness
   probe for the new dependency.
5. `resilience-patterns` —
   circuit breaker + retry on the `*Client`.
6. `observability` — MDC correlation
   ID propagated in outbound headers.
7. `unit-tests` — every layer.
8. `integration-tests` —
   WireMock for the HTTP boundary.
9. `adapter-contract-tests`
   — if multiple adapters exist, a TCK per port.

## Information to gather before generating

```
1. Service display name (e.g. "Product Catalogue Service")
2. Sub-package name: lower-case, no hyphens — hyphens are illegal in Java package names (e.g. `productcatalogue`)
3. Base URL config key — kebab-case is fine here (e.g. product-catalogue.base-url)
4. Operations to expose: HTTP method + path + purpose (list each) — and how many you expect within 6 months (decides the pattern, `external-client` §0)
5. Auth mechanism (none / bearer passthrough / OAuth2 client credentials / basic)
6. Connect timeout / read timeout in ms
7. Is idempotent (safe to retry)?
8. Does this need a domain metric? (→ also invoke the `ai-toolkit-java-agents:new-metric` agent)
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

## Delegation (use subagents when you can)

Follow the `ai-toolkit-workflow:parallel-delegation` skill. Subagents cannot spawn subagents: if the Agent tool is
available you are the main-session agent (`claude --agent`) — delegate as below; if it is not,
do the same steps inline, in order. Call subagents by their **qualified name** —
`ai-toolkit-java-agents:test-writer`, `ai-toolkit-java-agents:code-review`, `ai-toolkit-docs:update-context`,
`general-purpose`. The original step order above is binding: fan out only work that is independent, and only
once the code it depends on exists.

1. **Sequential (you):** gather the information above, then create the `client/<dep>/` skeleton — constants,
   `*ClientConfig`, `*Client`, the `*Service` facade — and the domain exception for non-2xx.
2. **Parallel leaves (optional, disjoint files, after step 1):** `general-purpose` for the request builders
   (`*RequestBuilder`, `*FilterMapBuilder`), `general-purpose` for the response parser + verifier,
   `general-purpose` for the readiness `HealthIndicator` and the resilience / observability wiring.
3. **Sequential (you):** wire the leaves into `*CoreService` and add the `application.yaml` keys.
4. **Parallel fan-out, one message — after the code exists:** `ai-toolkit-java-agents:test-writer` for unit tests
   per layer; `ai-toolkit-java-agents:test-writer` for the WireMock integration test `*IT` (`integration-tests`) and,
   if several adapters exist, one TCK per port (`adapter-contract-tests`) — written, not run;
   `ai-toolkit-docs:update-context` — dependencies doc + CHANGELOG.
5. **Sequential (you):** run the build and tests, then `ai-toolkit-java-agents:code-review`.

Keep shared files (`pom.xml`, `application.yaml`, `ExceptionMessages`, `api.yaml`) and **every build and test run**
to yourself — tell each test-writer in its brief: "do not run builds or tests; the main thread owns builds".
Verify every result (read the diff, run the tests) before reporting done.

## Commit policy and completion gate

Never `git commit`, `git push` or tag — leave the changes in the working tree until the developer asks.
Before reporting the task done, run the `ai-toolkit-quality:completion-gate` skill (build, full tests, static analysis,
`quality-review`, coverage of the changed code, `ai-toolkit-quality:code-hygiene`, Sonar) and finish with its evidence
table. Fix failures at the cause; never suppress or weaken a check to get green.

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
- [ ] `ai-toolkit-quality:completion-gate` evidence table produced; nothing committed.

---
name: new-microservice-client
description: Java / Spring Boot — integrate a new downstream microservice or external API using the canonical `client/<dep>/` package (Simple Wrapper, Lite or five-layer — the simplest that fits its scale).
---

# Agent: New Microservice Client

> **Purpose:** Integrate a new downstream microservice or external API
> using the canonical `client/<dep>/` package (Simple Wrapper, Lite or
> five-layer — the simplest that fits, `ai-toolkit-java-build:external-client` §0).

---

You are a backend-coding agent for a Java 21 / Spring Boot microservice.
The developer wants to call a **new external service**. You will produce
the full integration package.

## Skills to apply (in this order)

Load each skill with the Skill tool, by its qualified name, first — before any CLARIFY question or code — do not work from memory. Also
load `ai-toolkit-quality:completion-gate` and `ai-toolkit-quality:code-hygiene` before you finish (see the gate below).

1. `ai-toolkit-java-build:external-client` — first ask the scale questions in its §0 (how many endpoints now / in 6 months, query and response complexity) and choose
   Simple Wrapper, Lite or the full five-layer structure (Service, CoreService, Client, handler/, constant/). Default to the simplest that fits.
2. `ai-toolkit-java-design:pluggable-architecture`
   — if multiple backends could serve the same capability, expose
   `*Service` as a port interface and put adapters under `adapter/`.
3. `ai-toolkit-java-build:exception-handling` —
   domain exception for non-2xx from the Client.
4. `ai-toolkit-java-ops:health-indicator` — readiness
   probe for the new dependency.
5. `ai-toolkit-java-build:resilience-patterns` —
   circuit breaker + retry on the `*Client`.
6. `ai-toolkit-java-ops:observability` — W3C trace context (`traceparent`)
   propagates automatically through the auto-configured `RestClient.Builder` /
   `WebClient.Builder`; build the client from that builder and never invent a
   custom correlation header.
7. `ai-toolkit-java-quality:unit-tests` — every layer.
8. `ai-toolkit-java-quality:integration-tests` —
   WireMock for the HTTP boundary.
9. `ai-toolkit-java-quality:adapter-contract-tests`
   — if multiple adapters exist, a TCK per port.

## Information to gather before generating

```
1. Service display name (e.g. "Product Catalogue Service")
2. Sub-package name: lower-case, no hyphens — hyphens are illegal in Java package names (e.g. `productcatalogue`)
3. Base URL config key — kebab-case is fine here (e.g. product-catalogue.base-url)
4. Operations to expose: HTTP method + path + purpose (list each) — and how many you expect within 6 months (decides the pattern, `ai-toolkit-java-build:external-client` §0)
5. Auth mechanism (none / bearer passthrough / OAuth2 client credentials / basic)
6. Connect timeout / read timeout in ms
7. Is idempotent (safe to retry)?
8. Does this need a domain metric? (→ also apply the `ai-toolkit-java-ops:request-metrics` skill yourself, following the
   `ai-toolkit-java-agents:new-metric` procedure, or tell the developer to run that agent afterwards)
9. Query and response complexity — filters / DSL, nested transformations (`ai-toolkit-java-build:external-client` §0)
10. Readiness probe (`ai-toolkit-java-ops:health-indicator`): the downstream's readiness endpoint, expected success
    status code and probe interval
```

Ask all of these in one round, before generating anything.

## Generated file list

One list per pattern (`ai-toolkit-java-build:external-client` §0). Simple Wrapper and Lite use `RestClient`; callers
import only `<Dep>Client`. Full 5-Layer callers import only `<Dep>Service`.

```
Simple Wrapper:                     Lite:
client/<dep>/                       client/<dep>/
  <Dep>Client.java                    <Dep>Client.java
  <Dep>ClientConfig.java              <Dep>ClientConfig.java
  <Dep>Properties.java                <Dep>Properties.java
                                      <Dep>RequestBuilder.java
                                      <Dep>ResponseParser.java

Full 5-Layer:
client/<dep>/
  <Dep>Service.java
  constant/<Dep>Constants.java
  core/
    <Dep>ClientConfig.java
    <Dep>Properties.java                  (@ConfigurationProperties record)
    <Dep>Client.java
    <Dep>CoreService.java
  handler/
    request/<Dep>RequestBuilder.java
    request/<Dep>FilterMapBuilder.java    (if filter-map style queries)
    response/<Dep>ResponseParser.java
    response/<Dep>ResponseVerifier.java

Every pattern:
health/indicator/<Dep>HealthIndicator.java
application.yaml additions
```

## Questions when you run as a subagent

A subagent cannot ask the developer — only the main session can. If a CLARIFY / ASK question or a confirmation
step is still open and your brief does not answer it, write no files: return `NEEDS INPUT:` with the numbered
questions and the default you would assume for each, then stop. The caller asks the developer in the main session
and invokes you again with the answers. Never invent the answer to a HITL question.

## Delegation (use subagents when you can)

Follow the `ai-toolkit-workflow:parallel-delegation` skill. Delegate as below whenever the Agent tool is available —
also when you run as a subagent yourself (a subagent can start subagents); if it is not available, do the same
steps inline, in order. Call subagents by their **qualified name** —
`ai-toolkit-java-agents:test-writer`, `ai-toolkit-java-agents:code-review`, `ai-toolkit-docs:update-context`,
`general-purpose`. The original step order above is binding: fan out only work that is independent, and only
once the code it depends on exists.

1. **Sequential (you):** gather the information above (one round, including the readiness-probe answers), choose the
   pattern, then create the `client/<dep>/` skeleton — `*Properties`, `*ClientConfig`, `*Client` and, for Full 5-Layer,
   constants and the `*Service` facade — and the domain exception for non-2xx. **Simple Wrapper or Lite: write the
   whole package yourself and skip step 2.**
2. **Parallel leaves — Full 5-Layer only (optional, disjoint files, after step 1):** `general-purpose` for the request
   builders (`*RequestBuilder`, `*FilterMapBuilder`) and `general-purpose` for the response parser + verifier.
3. **Sequential (you):** wire the leaves into `*CoreService` (Full 5-Layer); add the resilience and observability
   wiring on `*Client` and the `application.yaml` keys; apply `ai-toolkit-java-ops:health-indicator` yourself with the
   answers from step 1 — it edits shared files (`application.yaml`, Helm chart); if item 8 is yes, add the domain metric
   with `ai-toolkit-java-ops:request-metrics` (the `ai-toolkit-java-agents:new-metric` procedure).
4. **Parallel fan-out, one message — after the code exists:** `ai-toolkit-java-agents:test-writer` for unit tests
   per layer; `ai-toolkit-java-agents:test-writer` for the WireMock integration test `*IT` (`ai-toolkit-java-quality:integration-tests`) and,
   if several adapters exist, one TCK per port (`ai-toolkit-java-quality:adapter-contract-tests`) — written, not run;
   `ai-toolkit-docs:update-context` — dependencies doc + CHANGELOG (only when no release bot owns it).
5. **Sequential (you):** run the build and tests, then `ai-toolkit-java-agents:code-review`.

Keep shared files (`pom.xml`, `application.yaml`, `ExceptionMessages`, `api.yaml`, and shared test infrastructure such
as `ComponentTestConfiguration`, the test-profile yaml and common fixtures) and **every build and test run** to yourself;
add the test doubles and fixtures the tests need before the fan-out. Tell each subagent in its brief: "do not run
builds or tests; the main thread owns builds" and "never stage, commit, push or stash".
Verify every result (read the diff, run the tests) before reporting done.

## Commit policy and completion gate

Never `git commit`, `git push`, `git stash` or tag — leave the changes in the working tree until the developer asks.
Before reporting the task done, run the `ai-toolkit-quality:completion-gate` skill — all nine checks: scope, build, full
tests plus the PIT run, static analysis, standards (`ai-toolkit-java-quality:quality-review`), coverage of the changed
code, `ai-toolkit-quality:code-hygiene`, Sonar, docs — and finish with its evidence table. Commands are shown for Maven;
on a Gradle build use the project's wrapper equivalent (`./gradlew build`). Fix failures at the cause; never suppress or
weaken a check to get green. Return the evidence table to your caller unchanged, so it can relay it instead of running
the gate a second time.
Gate check 5 (Standards) is the `ai-toolkit-java-agents:code-review` run from the delegation plan above: reuse its report as the
evidence instead of reviewing a second time; re-run it only if you changed code after it. Without the Agent tool,
run check 5 inline: apply `ai-toolkit-java-quality:quality-review` and `ai-toolkit-java-quality:golden-path` to the whole
diff, including untracked files.

## Checklist before returning

- [ ] Callers import only the package's public entry type — `*Service` (Full 5-Layer) or `*Client` (Simple / Lite);
      no remote DTO or transport type escapes the package.
- [ ] All non-2xx responses throw a domain exception. Full 5-Layer only: `*Client` uses the `exchangeToMono` +
      `handleResponse` pattern.
- [ ] Full 5-Layer only: `*FilterMapBuilder` is a non-Spring plain object (`new`), not a bean.
- [ ] Full 5-Layer only: `*ResponseParser` (extract values) is separate from
      `*ResponseVerifier` (boolean checks).
- [ ] Constants (the Constants file in Full 5-Layer) hold all remote field names / endpoint paths.
- [ ] Base URL and timeouts bound through the `*Properties` `@ConfigurationProperties` record.
- [ ] Circuit breaker + retry wired in `*Client` via Resilience4j.
- [ ] Readiness `HealthIndicator` added.
- [ ] `application.yaml` keys added with `${ENV_VAR:default}` placeholders.
- [ ] Unit tests cover every layer; WireMock integration test covers
      happy path + 5xx error path.
- [ ] `context/dependencies.md` updated.
- [ ] CHANGELOG updated — only when no release bot owns it (`ai-toolkit-workflow:release-versioning`).
- [ ] `ai-toolkit-quality:completion-gate` evidence table produced; nothing committed.

# Public Skills

Vendor-neutral skills for bootstrapping and maintaining a Java 21 /
Spring Boot microservice. No proprietary BOM, no proprietary starters,
no proprietary Jenkins shared library, no proprietary JWT shape, no
proprietary authorization services, no private registries.

A consumer who can resolve only public Maven Central artifacts and pull
from any OCI registry can apply these skills as-is and end up with a
working microservice.

> See [`./REGISTRY.md`](./REGISTRY.md) for the machine-readable index
> of every skill, [`./AUTHORING.md`](./AUTHORING.md) for the SKILL.md
> authoring contract, and [`./BACKEND_GUILD.md`](./BACKEND_GUILD.md)
> for the curated MUST / SHOULD / MAY adoption bundle.

| Skill | Purpose |
| --- | --- |
| **Meta** | |
| [`project-types`](./project-types/SKILL.md) | **Entry point.** Picks the right combination of skills for the kind of project (sync REST / event-driven / scheduler / library / monolith-with-bones) and pre-fills `create-repo`. |
| [`create-repo`](./create-repo/SKILL.md) | **HITL** end-to-end scaffolder that orchestrates the skills below to bootstrap a new repository. |
| [`refactoring-playbook`](./refactoring-playbook/SKILL.md) | Step-by-step migrations from common anti-patterns to canonical patterns shipped by the other skills. |
| **Documentation** | |
| [`context-maintenance`](./context-maintenance/SKILL.md) | Maintain project context documentation (architecture, standards, progress) for AI assistants and team members. |
| [`uml-diagram`](./uml-diagram/SKILL.md) | Create and maintain Mermaid diagrams to visualize system architecture and interaction flows. Renders natively on GitHub / GitLab without external tools. |
| [`documentation-and-adr`](./documentation-and-adr/SKILL.md) | README / CONTRIBUTING / ARCHITECTURE + C4 diagrams (PlantUML) + Architecture Decision Records under `docs/adr/`. |
| **Architecture & code** | |
| [`pluggable-architecture`](./pluggable-architecture/SKILL.md) | **Cross-cutting policy.** Every external technology (cache, DB dialect, metrics backend, broker, …) sits behind a project-owned port and is supplied by vendor adapters selected/composed purely by configuration — swap or multi-provider by config, never by editing business logic. ArchUnit-enforced. |
| [`testable-code-principles`](./testable-code-principles/SKILL.md) | **Foundational.** LEGO Bricks principle (small, focused, self-explanatory), SDK-like design (document through names not comments), SOLID → testability mapping, avoiding anti-patterns (static methods, global state, hidden side effects). Reference for all code and quality reviews. |
| [`strategy-registry-pattern`](./strategy-registry-pattern/SKILL.md) | **Foundational.** Pluggable, extensible behaviour via Strategy + Registry + Handler/Filter — add a new behaviour by adding one strategy class, never by editing the dispatcher (Open/Closed). Handler-based (sync) and Filter-based (request-scoped) variations. Referenced by `response-layout`, `response-mapper`, `request-metrics`, `permissions`. |
| [`validation-pattern`](./validation-pattern/SKILL.md) | **Foundational.** Declarative input validation with separation of concerns — Jakarta `ConstraintValidator` (field/param) + Spring `Validator` (object/cross-field) + domain rule beans + `ValidationConfig`. Referenced by `input-validation`. |
| [`code-structure`](./code-structure/SKILL.md) | Package layout, SOLID mapping, lego sub-interface trick, composition-over-inheritance + Tell-Don't-Ask + Law of Demeter, immutability + visibility, ArchUnit enforcement, 12-pattern catalogue with anti-patterns. |
| [`domain-modeling`](./domain-modeling/SKILL.md) | DDD tactical patterns — Bounded Context, Aggregate Root, Value Object, Domain Event, Domain Service, Repository, Anti-Corruption Layer, Specification. |
| [`spring-boot-conventions`](./spring-boot-conventions/SKILL.md) | Canonical Spring Boot 3 idioms (typed `@ConfigurationProperties`, profiles, `@Conditional*`, validation, springdoc, `Pageable`, `@Async`, **`@Scheduled` §7b**, caching, idempotency, events, `RestClient`, `Clock`). |
| [`data-privacy`](./data-privacy/SKILL.md) | Handle PII and GDPR: field-level encryption, masking in logs, data retention (TTL), right-to-be-forgotten, and auditing. |
| [`feature-flags`](./feature-flags/SKILL.md) | Decouple deployment from release: Release, Experiment, Ops, and Permission toggles; structural toggles with `@ConditionalOnProperty`. |
| [`resilience-patterns`](./resilience-patterns/SKILL.md) | Bulkhead, Circuit Breaker, adaptive concurrency limits, and fallback strategies using Resilience4j. |
| [`api-design`](./api-design/SKILL.md) | REST resource modelling, status code catalogue, versioning, pagination + filtering + sorting, deprecation headers, **multipart endpoints (§6b)**, OpenAPI-first vs code-first. |
| [`async-api-patterns`](./async-api-patterns/SKILL.md) | Handle long-running operations: Submit-Poll-Result, Webhooks with HMAC signing, and Server-Sent Events (SSE). |
| [`response-layout`](./response-layout/SKILL.md) | Layout query parameter (`?layout=summary/detailed/full`) support — `LayoutHandler` resolves the layout, routes via a registry to a `LayoutStrategy`, returns a tailored DTO. Add a layout by adding one strategy. Application of `strategy-registry-pattern`. |
| [`response-mapper`](./response-mapper/SKILL.md) | API versioning & response projection mapping — `MapperHandler` resolves the target version/projection (Accept header / URI / query param), routes via a registry to a `MapperStrategy`, returns a version-specific DTO. Add a version by adding one strategy. Application of `strategy-registry-pattern`. |
| [`openapi-first-codegen`](./openapi-first-codegen/SKILL.md) | Drive controllers and DTOs from `api.yaml` via `openapi-generator-maven-plugin` — controllers implement generated `<Resource>Api`, generated DTOs never leak past the controller, generated sources excluded from coverage / static analysis. |
| [`exception-handling`](./exception-handling/SKILL.md) | Domain exception hierarchy + `ExceptionMessages` + `@RestControllerAdvice` → RFC 7807 `ProblemDetail`. |
| [`input-validation`](./input-validation/SKILL.md) | Custom Jakarta `ConstraintValidator` (annotation-driven, Spring-bean-aware, parameter/field level) and Spring `Validator` (object/cross-field level) with reusable domain rule beans, custom violation messages, `@InitBinder` registration, and test patterns. |
| [`permissions`](./permissions/SKILL.md) | Pluggable Strategy + Handler authorization with `CallerContextResolver` / `ResourceAuthorizationSource` SPIs. |
| [`graceful-shutdown`](./graceful-shutdown/SKILL.md) | `server.shutdown=graceful` + K8s `terminationGracePeriodSeconds` + executor / consumer / pool drain. |
| **External boundaries** | |
| [`external-client`](./external-client/SKILL.md) | Consumer side of the lego brick — five-layer SDK-style sub-package (`*Service` facade → `*CoreService` orchestrator → `*Client` transport, `handler/request` with `*RequestBuilder` + `*FilterMapBuilder`, `handler/response` with `*ResponseParser` + `*ResponseVerifier`, `constant/*Constants`). |
| [`sdk-publishing`](./sdk-publishing/SKILL.md) | Producer side — turn an internal module into a Spring Boot starter (auto-config with `@ConditionalOnMissingBean` defaults, configuration metadata, SemVer + deprecation). |
| [`messaging`](./messaging/SKILL.md) | Async messaging (Kafka / RabbitMQ): immutable events, transactional outbox, idempotent consumer, DLQ, schema evolution. |
| [`rate-limiting`](./rate-limiting/SKILL.md) | Protect from abuse: token bucket, sliding window; local enforcement (Bucket4j, Resilience4j) and distributed limiting (Redis). |
| [`persistence`](./persistence/SKILL.md) | Spring Data JPA + **Flyway (§3) or Liquibase (§3b)** forward-only migrations + `@Version` optimistic locking + auditing + Specification pattern + transaction boundaries + N+1 prevention. |
| **Build, deploy, operate** | |
| [`ci`](./ci/SKILL.md) | Vendor-neutral Jenkins declarative pipeline + Dockerfile + Maven `pom.xml`. |
| [`github-actions-ci`](./github-actions-ci/SKILL.md) | Same contract as `ci` but for GitHub Actions (build / image / release / Trivy / cosign / SBOM / Dependabot). |
| [`cd`](./cd/SKILL.md) | Vendor-neutral hardened Helm chart. |
| [`health-indicator`](./health-indicator/SKILL.md) | **HITL** — Spring Boot Actuator readiness `HealthIndicator` for any downstream dependency. |
| [`observability`](./observability/SKILL.md) | Three pillars: Micrometer + Prometheus metrics, JSON logs with MDC, OpenTelemetry traces; SLI/SLO contract; dashboards-as-code. |
| [`request-metrics`](./request-metrics/SKILL.md) | Per-request domain metrics: `OncePerRequestFilter` measures latency, `MetricNameResolver` routes by URI regex, pluggable `MetricsRecorder` per use case (Strategy + Registry), `parser/` extracts structured tags (method, status, clientId, domain tags), `MetricsTimerHelper` publishes SLO-bucketed Timers. Add a new metric by adding one recorder. |
| [`security-hardening`](./security-hardening/SKILL.md) | OWASP Top 10 mitigations, CORS, rate limiting, secrets management, dependency scanning, image signing, security headers, actuator lockdown. |
| **Quality** | |
| [`unit-tests`](./unit-tests/SKILL.md) | JUnit 5 + Mockito + AssertJ + Test Data Builders + parameterized variants + `MockedStatic` + PIT mutation testing + ArchUnit + WireMock / MockWebServer + optional jqwik. |
| [`component-tests`](./component-tests/SKILL.md) | Spring Boot component tests with deterministic boundary fakes, opt-out `@TestConfiguration`s, JWT post-processors for secured paths, JsonPath, snapshot/golden-file pattern. |
| [`integration-tests`](./integration-tests/SKILL.md) | Testcontainers (Postgres / Kafka / MinIO / LocalStack) + Surefire / Failsafe split + WireMock + Pact / Spring Cloud Contract. |
| [`static-analysis`](./static-analysis/SKILL.md) | Spotless + SpotBugs + FindSecBugs + Error-Prone + NullAway + optional Sonar. |
| [`quality-review`](./quality-review/SKILL.md) | SOLID / clean-code / testability audit with **43 items** including testability anti-patterns (static methods, global state), positive & negative test coverage, and quantitative thresholds (complexity ≤ 10, method ≤ 30 LOC, mutation score ≥ 75 %, …). |
| [`adapter-contract-tests`](./adapter-contract-tests/SKILL.md) | TCK-style shared abstract test suite per port, run against every adapter so swapping a provider cannot change business behaviour — proves the lego-brick contract. |
| **Lifecycle** | |
| [`release-versioning`](./release-versioning/SKILL.md) | Conventional Commits + SemVer + `release-please` / `semantic-release` + CHANGELOG generation + deprecation policy. |
| [`local-dev-experience`](./local-dev-experience/SKILL.md) | `docker-compose.yml` for deps, `Makefile`, `.devcontainer`, `.editorconfig`, pre-commit hooks. |

## Extension points (where to plug in for org-specific bindings)

The public skills deliberately expose **SPIs and configuration knobs** instead
of hard-coding any organization-specific dependency. A private fork can
add wrappers / starters that fill these in without modifying the
catalogue:

| Public extension point | Typical organization-specific binding |
| --- | --- |
| Spring Boot parent + plain dependencies | An organization-managed BOM and curated starters |
| Vanilla Jenkins declarative pipeline | A one-line call to a private shared library that runs build / sign / scan / push |
| Plain image registry placeholder | Organization registry + image-pull secret + signed-image policy |
| `ResponseEntityExceptionHandler` base class | An organization-specific advice base that adds trace IDs, request URIs, and standardized error codes |
| `CallerContextResolver` SPI | A resolver that reads the organization's custom authentication token shape |
| `ResourceAuthorizationSource` SPI | A client to the organization's authorization / search service |
| Generic `*Client` template | Pre-wired clients for in-house file storage, search, analytics, etc. |
| `<shared-auth-config>` placeholder in Helm | Reference to the organization's shared auth ConfigMap
## Maintainer references

| Resource | Purpose |
| --- | --- |
| [`./BACKEND_GUILD.md`](./BACKEND_GUILD.md) | Curated MUST / SHOULD / MAY adoption matrix + apply-order + task-driven recipes + non-negotiables for code review. |
| [`./REGISTRY.md`](./REGISTRY.md) | Machine-readable index of every skill (counts, templates indicator). |
| [`./AUTHORING.md`](./AUTHORING.md) | SKILL.md authoring contract — frontmatter rules, required sections, placeholder syntax, checklist. |
| [`./validate-skills.sh`](./validate-skills.sh) | CI-friendly linter — fails on missing frontmatter, mismatched folder/`name`, broken template links, missing registry entries. |

Run the validator before opening a PR that touches `public/skills/`:

```sh
bash validate-skills.sh
```

## Optional publication-safety check

If you maintain a private fork that adds organization-specific terms you do
not want leaking into shared skill files, create a `.publication-blocklist`
file at the `copilot/` root (one substring per line, `#` for comments). The
validator's publication-safety check fails the build if any blocklisted term
appears in any `*.md` under `public/`. The shipped catalogue contains no such
file and the check is a no-op by default.


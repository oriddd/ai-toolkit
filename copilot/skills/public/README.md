# Public Skills

Vendor-neutral skills for bootstrapping and maintaining a Java 21 /
Spring Boot microservice. No proprietary BOM, no proprietary starters,
no proprietary Jenkins shared library, no proprietary JWT shape, no
proprietary authorization services, no private registries.

A consumer who can resolve only public Maven Central artifacts and pull
from any OCI registry can apply these skills as-is and end up with a
working microservice.

> See [`../REGISTRY.md`](../REGISTRY.md) for the machine-readable index
> of every skill, [`../AUTHORING.md`](../AUTHORING.md) for the SKILL.md
> authoring contract, and [`../BACKEND_GUILD.md`](../BACKEND_GUILD.md)
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
| [`code-structure`](./code-structure/SKILL.md) | Package layout, SOLID mapping, lego sub-interface trick, composition-over-inheritance + Tell-Don't-Ask + Law of Demeter, immutability + visibility, ArchUnit enforcement, 12-pattern catalogue with anti-patterns. |
| [`domain-modeling`](./domain-modeling/SKILL.md) | DDD tactical patterns — Bounded Context, Aggregate Root, Value Object, Domain Event, Domain Service, Repository, Anti-Corruption Layer, Specification. |
| [`spring-boot-conventions`](./spring-boot-conventions/SKILL.md) | Canonical Spring Boot 3 idioms (typed `@ConfigurationProperties`, profiles, `@Conditional*`, validation, springdoc, `Pageable`, `@Async`, **`@Scheduled` §7b**, caching, idempotency, events, `RestClient`, `Clock`). |
| [`data-privacy`](./data-privacy/SKILL.md) | Handle PII and GDPR: field-level encryption, masking in logs, data retention (TTL), right-to-be-forgotten, and auditing. |
| [`feature-flags`](./feature-flags/SKILL.md) | Decouple deployment from release: Release, Experiment, Ops, and Permission toggles; structural toggles with `@ConditionalOnProperty`. |
| [`resilience-patterns`](./resilience-patterns/SKILL.md) | Bulkhead, Circuit Breaker, adaptive concurrency limits, and fallback strategies using Resilience4j. |
| [`api-design`](./api-design/SKILL.md) | REST resource modelling, status code catalogue, versioning, pagination + filtering + sorting, deprecation headers, **multipart endpoints (§6b)**, OpenAPI-first vs code-first. |
| [`async-api-patterns`](./async-api-patterns/SKILL.md) | Handle long-running operations: Submit-Poll-Result, Webhooks with HMAC signing, and Server-Sent Events (SSE). |
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
| [`quality-review`](./quality-review/SKILL.md) | SOLID / clean-code audit with **33 items** including quantitative thresholds (complexity ≤ 10, method ≤ 30 LOC, mutation score ≥ 75 %, …). |
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
| `<shared-auth-config>` placeholder in Helm | Reference to the organization's shared auth ConfigMap |

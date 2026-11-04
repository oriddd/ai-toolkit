# Skills Index

Vendor-neutral skills for bootstrapping and maintaining services and apps — Java 21 / Spring Boot,
Python and React Native — plus language-neutral workflow, documentation and quality skills. They need only
public dependencies (Maven Central, PyPI, npm) and any OCI registry; no private artifacts, starters, shared
libraries or token shapes are assumed.

> See [`./REGISTRY.md`](./REGISTRY.md) for the machine-readable index
> of every skill, [`./AUTHORING.md`](./AUTHORING.md) for the SKILL.md
> authoring contract, and [`./BACKEND_GUILD.md`](./BACKEND_GUILD.md)
> for the curated MUST / SHOULD / MAY adoption bundle.

| Skill | Purpose |
| --- | --- |
| **Meta** | |
| [`project-types`](../plugins/ai-toolkit-java-scaffold/skills/project-types/SKILL.md) | **Entry point.** Picks the right combination of skills for the kind of project (sync REST / event-driven / scheduler / library / monolith-with-bones) and pre-fills `create-repo`. |
| [`create-repo`](../plugins/ai-toolkit-java-scaffold/skills/create-repo/SKILL.md) | **HITL** end-to-end scaffolder that orchestrates the skills below to bootstrap a new repository. |
| [`refactoring-playbook`](../plugins/ai-toolkit-java-quality/skills/refactoring-playbook/SKILL.md) | Step-by-step migrations from common anti-patterns to canonical patterns shipped by the other skills. |
| **Documentation** | |
| [`context-maintenance`](../plugins/ai-toolkit-docs/skills/context-maintenance/SKILL.md) | Maintain project context documentation (architecture, standards, progress) for AI assistants and team members. |
| [`uml-diagram`](../plugins/ai-toolkit-docs/skills/uml-diagram/SKILL.md) | Create and maintain Mermaid diagrams to visualize system architecture and interaction flows. Renders natively on GitHub / GitLab without external tools. |
| [`documentation-and-adr`](../plugins/ai-toolkit-docs/skills/documentation-and-adr/SKILL.md) | README / CONTRIBUTING / ARCHITECTURE + C4 diagrams (PlantUML) + Architecture Decision Records under `docs/adr/`. |
| **Architecture & code** | |
| [`pluggable-architecture`](../plugins/ai-toolkit-java-design/skills/pluggable-architecture/SKILL.md) | **Cross-cutting policy.** Every external technology (cache, DB dialect, metrics backend, broker, …) sits behind a project-owned port and is supplied by vendor adapters selected/composed purely by configuration — swap or multi-provider by config, never by editing business logic. ArchUnit-enforced. |
| [`testable-code-principles`](../plugins/ai-toolkit-java-design/skills/testable-code-principles/SKILL.md) | **Foundational.** LEGO Bricks principle (small, focused, self-explanatory), SDK-like design (document through names not comments), SOLID → testability mapping, avoiding anti-patterns (static methods, global state, hidden side effects). Reference for all code and quality reviews. |
| [`golden-path`](../plugins/ai-toolkit-java-quality/skills/golden-path/SKILL.md) | The Java / Spring Boot golden path: apply-order and the 24 non-negotiables (generated from `BACKEND_GUILD.md`). |
| [`pattern-selection`](../plugins/ai-toolkit-java-design/skills/pattern-selection/SKILL.md) | Choose the smallest pattern that fits — prevents over-engineering (generated from `PATTERN_SELECTION_GUIDE.md`). |
| [`parallel-delegation`](../plugins/ai-toolkit-workflow/skills/parallel-delegation/SKILL.md) | When and how to hand independent work to subagents in parallel — what to delegate, file ownership, writing the brief, verifying results. |
| [`strategy-registry-pattern`](../plugins/ai-toolkit-java-design/skills/strategy-registry-pattern/SKILL.md) | **Foundational.** Pluggable, extensible behaviour via Strategy + Registry + Handler/Filter — add a new behaviour by adding one strategy class, never by editing the dispatcher (Open/Closed). Handler-based (sync) and Filter-based (request-scoped) variations. Referenced by `response-layout`, `response-mapper`, `request-metrics`, `permissions`. |
| [`validation-pattern`](../plugins/ai-toolkit-java-build/skills/validation-pattern/SKILL.md) | **Foundational.** Declarative input validation with separation of concerns — Jakarta `ConstraintValidator` (field/param) + Spring `Validator` (object/cross-field) + domain rule beans + `ValidationConfig`. Referenced by `input-validation`. |
| [`code-structure`](../plugins/ai-toolkit-java-design/skills/code-structure/SKILL.md) | Package layout, SOLID mapping, lego sub-interface trick, composition-over-inheritance + Tell-Don't-Ask + Law of Demeter, immutability + visibility, ArchUnit enforcement, 12-pattern catalogue with anti-patterns. |
| [`domain-modeling`](../plugins/ai-toolkit-java-design/skills/domain-modeling/SKILL.md) | DDD tactical patterns — Bounded Context, Aggregate Root, Value Object, Domain Event, Domain Service, Repository, Anti-Corruption Layer, Specification. |
| [`spring-boot-conventions`](../plugins/ai-toolkit-java-design/skills/spring-boot-conventions/SKILL.md) | Canonical Spring Boot 3 idioms (typed `@ConfigurationProperties`, profiles, `@Conditional*`, validation, springdoc, `Pageable`, `@Async`, **`@Scheduled` §7b**, caching, idempotency, events, `RestClient`, `Clock`). |
| [`data-privacy`](../plugins/ai-toolkit-java-build/skills/data-privacy/SKILL.md) | Handle PII and GDPR: field-level encryption, masking in logs, data retention (TTL), right-to-be-forgotten, and auditing. |
| [`feature-flags`](../plugins/ai-toolkit-java-design/skills/feature-flags/SKILL.md) | Decouple deployment from release: Release, Experiment, Ops, and Permission toggles; structural toggles with `@ConditionalOnProperty`. |
| [`resilience-patterns`](../plugins/ai-toolkit-java-build/skills/resilience-patterns/SKILL.md) | Bulkhead, Circuit Breaker, adaptive concurrency limits, and fallback strategies using Resilience4j. |
| [`api-design`](../plugins/ai-toolkit-java-design/skills/api-design/SKILL.md) | REST resource modelling, status code catalogue, versioning, pagination + filtering + sorting, deprecation headers, **multipart endpoints (§6b)**, OpenAPI-first vs code-first. |
| [`async-api-patterns`](../plugins/ai-toolkit-java-design/skills/async-api-patterns/SKILL.md) | Handle long-running operations: Submit-Poll-Result, Webhooks with HMAC signing, and Server-Sent Events (SSE). |
| [`response-layout`](../plugins/ai-toolkit-java-design/skills/response-layout/SKILL.md) | Layout query parameter (`?layout=summary/detailed/full`) support — `LayoutHandler` resolves the layout, routes via a registry to a `LayoutStrategy`, returns a tailored DTO. Add a layout by adding one strategy. Application of `strategy-registry-pattern`. |
| [`response-mapper`](../plugins/ai-toolkit-java-design/skills/response-mapper/SKILL.md) | API versioning & response projection mapping — `MapperHandler` resolves the target version/projection (Accept header / URI / query param), routes via a registry to a `MapperStrategy`, returns a version-specific DTO. Add a version by adding one strategy. Application of `strategy-registry-pattern`. |
| [`openapi-first-codegen`](../plugins/ai-toolkit-java-design/skills/openapi-first-codegen/SKILL.md) | Drive controllers and DTOs from `api.yaml` via `openapi-generator-maven-plugin` — controllers implement generated `<Resource>Api`, generated DTOs never leak past the controller, generated sources excluded from coverage / static analysis. |
| [`exception-handling`](../plugins/ai-toolkit-java-build/skills/exception-handling/SKILL.md) | Domain exception hierarchy + `ExceptionMessages` + `@RestControllerAdvice` → RFC 7807 `ProblemDetail`. |
| [`input-validation`](../plugins/ai-toolkit-java-build/skills/input-validation/SKILL.md) | Custom Jakarta `ConstraintValidator` (annotation-driven, Spring-bean-aware, parameter/field level) and Spring `Validator` (object/cross-field level) with reusable domain rule beans, custom violation messages, `@InitBinder` registration, and test patterns. |
| [`permissions`](../plugins/ai-toolkit-java-build/skills/permissions/SKILL.md) | Pluggable Strategy + Handler authorization with `CallerContextResolver` / `ResourceAuthorizationSource` SPIs. |
| [`graceful-shutdown`](../plugins/ai-toolkit-java-ops/skills/graceful-shutdown/SKILL.md) | `server.shutdown=graceful` + K8s `terminationGracePeriodSeconds` + executor / consumer / pool drain. |
| **External boundaries** | |
| [`external-client`](../plugins/ai-toolkit-java-build/skills/external-client/SKILL.md) | Consumer side of the lego brick — five-layer SDK-style sub-package (`*Service` facade → `*CoreService` orchestrator → `*Client` transport, `handler/request` with `*RequestBuilder` + `*FilterMapBuilder`, `handler/response` with `*ResponseParser` + `*ResponseVerifier`, `constant/*Constants`). |
| [`sdk-publishing`](../plugins/ai-toolkit-java-build/skills/sdk-publishing/SKILL.md) | Producer side — turn an internal module into a Spring Boot starter (auto-config with `@ConditionalOnMissingBean` defaults, configuration metadata, SemVer + deprecation). |
| [`messaging`](../plugins/ai-toolkit-java-build/skills/messaging/SKILL.md) | Async messaging (Kafka / RabbitMQ): immutable events, transactional outbox, idempotent consumer, DLQ, schema evolution. |
| [`rate-limiting`](../plugins/ai-toolkit-java-build/skills/rate-limiting/SKILL.md) | Protect from abuse: token bucket, sliding window; local enforcement (Bucket4j, Resilience4j) and distributed limiting (Redis). |
| [`persistence`](../plugins/ai-toolkit-java-build/skills/persistence/SKILL.md) | Spring Data JPA + **Flyway (§3) or Liquibase (§3b)** forward-only migrations + `@Version` optimistic locking + auditing + Specification pattern + transaction boundaries + N+1 prevention. |
| **Build, deploy, operate** | |
| [`ci`](../plugins/ai-toolkit-java-ops/skills/ci/SKILL.md) | Vendor-neutral Jenkins declarative pipeline + Dockerfile + Maven `pom.xml`. |
| [`github-actions-ci`](../plugins/ai-toolkit-java-ops/skills/github-actions-ci/SKILL.md) | Same contract as `ci` but for GitHub Actions (build / image / release / Trivy / cosign / SBOM / Dependabot). |
| [`cd`](../plugins/ai-toolkit-java-ops/skills/cd/SKILL.md) | Vendor-neutral hardened Helm chart. |
| [`health-indicator`](../plugins/ai-toolkit-java-ops/skills/health-indicator/SKILL.md) | **HITL** — Spring Boot Actuator readiness `HealthIndicator` for any downstream dependency. |
| [`observability`](../plugins/ai-toolkit-java-ops/skills/observability/SKILL.md) | Three pillars: Micrometer + Prometheus metrics, JSON logs with MDC, OpenTelemetry traces; SLI/SLO contract; dashboards-as-code. |
| [`request-metrics`](../plugins/ai-toolkit-java-ops/skills/request-metrics/SKILL.md) | Per-request domain metrics: `OncePerRequestFilter` measures latency, `MetricNameResolver` routes by URI regex, pluggable `MetricsRecorder` per use case (Strategy + Registry), `parser/` extracts structured tags (method, status, clientId, domain tags), `MetricsTimerHelper` publishes SLO-bucketed Timers. Add a new metric by adding one recorder. |
| [`security-hardening`](../plugins/ai-toolkit-java-build/skills/security-hardening/SKILL.md) | OWASP Top 10 mitigations, CORS, rate limiting, secrets management, dependency scanning, image signing, security headers, actuator lockdown. |
| **Quality** | |
| [`unit-tests`](../plugins/ai-toolkit-java-quality/skills/unit-tests/SKILL.md) | JUnit 5 + Mockito + AssertJ + Test Data Builders + parameterized variants + `MockedStatic` + PIT mutation testing + ArchUnit + WireMock / MockWebServer + optional jqwik. |
| [`component-tests`](../plugins/ai-toolkit-java-quality/skills/component-tests/SKILL.md) | Spring Boot component tests with deterministic boundary fakes, opt-out `@TestConfiguration`s, JWT post-processors for secured paths, JsonPath, snapshot/golden-file pattern. |
| [`integration-tests`](../plugins/ai-toolkit-java-quality/skills/integration-tests/SKILL.md) | Testcontainers (Postgres / Kafka / MinIO / LocalStack) + Surefire / Failsafe split + WireMock + Pact / Spring Cloud Contract. |
| [`static-analysis`](../plugins/ai-toolkit-java-quality/skills/static-analysis/SKILL.md) | Spotless + SpotBugs + FindSecBugs + Error-Prone + NullAway + optional Sonar. |
| [`quality-review`](../plugins/ai-toolkit-java-quality/skills/quality-review/SKILL.md) | SOLID / clean-code / testability audit with **43 items** including testability anti-patterns (static methods, global state), positive & negative test coverage, and quantitative thresholds (complexity ≤ 10, method ≤ 30 LOC, mutation score ≥ 75 %, …). |
| [`adapter-contract-tests`](../plugins/ai-toolkit-java-quality/skills/adapter-contract-tests/SKILL.md) | TCK-style shared abstract test suite per port, run against every adapter so swapping a provider cannot change business behaviour — proves the lego-brick contract. |
| **Lifecycle** | |
| [`git-commit-conventions`](../plugins/ai-toolkit-workflow/skills/git-commit-conventions/SKILL.md) | Conventional Commit prefixes, small single-purpose commits, every commit compiles on its own, subject/body rules, commit-msg hook + interactive rebase clean-up, squash-vs-preserve policy for PRs. |
| [`pr-description`](../plugins/ai-toolkit-workflow/skills/pr-description/SKILL.md) | Write and update pull request descriptions on Bitbucket Server — structured sections (Problem, Solution, Key Changes, Testing, Notes), fetch + replace via REST API with optimistic locking, checklist for completeness. |
| [`release-versioning`](../plugins/ai-toolkit-workflow/skills/release-versioning/SKILL.md) | Conventional Commits + SemVer + `release-please` / `semantic-release` + CHANGELOG generation + deprecation policy. |
| [`local-dev-experience`](../plugins/ai-toolkit-java-ops/skills/local-dev-experience/SKILL.md) | `docker-compose.yml` for deps, `Makefile`, `.devcontainer`, `.editorconfig`, pre-commit hooks. |

## Definition of done (language-neutral)

`ai-toolkit-quality` is installed automatically with `ai-toolkit-workflow`. The workflow plugin's best-effort hook asks for confirmation before direct commits, pushes, tags and history rewrites (see `setup/claude-code/README.md` for what it cannot see).

| Skill | Plugin | Purpose |
| --- | --- | --- |
| [`completion-gate`](../plugins/ai-toolkit-quality/skills/completion-gate/SKILL.md) | `ai-toolkit-quality` | The definition of done for any implementation task — never commit or push until the user asks, then before reporting done prove the build passes, all tests pass, static analysis is clean, the diff meets the language standards, changed code is meaningfully covered with no redundant tests, hygiene is clean and the Sonar gate passes, with evidence for each. |
| [`code-hygiene`](../plugins/ai-toolkit-quality/skills/code-hygiene/SKILL.md) | `ai-toolkit-quality` | Keep a diff minimal and self-explanatory — no comments or docs that restate the code, no dead code, no speculative abstraction, no unrelated churn, and no redundant or meaningless tests. |
| [`sonar-quality-gate`](../plugins/ai-toolkit-quality/skills/sonar-quality-gate/SKILL.md) | `ai-toolkit-quality` | Run the project's SonarQube/SonarCloud analysis on your change and drive the new-code quality gate to green — bugs, vulnerabilities, code smells, security hotspots, duplication and coverage — without suppressing findings, and report honestly when Sonar cannot be reached. |

## Python (draft)

Language pilot — see [`LANGUAGE_CONTRACT.md`](./LANGUAGE_CONTRACT.md). Grouped by phase plugin.

| Skill | Plugin | Purpose |
| --- | --- | --- |
| [`python-code-structure`](../plugins/ai-toolkit-python-design/skills/python-code-structure/SKILL.md) | `ai-toolkit-python-design` | Apply the canonical Python 3.12 service layout (src layout, api/operations/services/clients/models/config layers, pydantic-settings, constructor injection, one-way dependency direction) where every module is a small single-purpose LEGO brick named so it documents itself. |
| [`python-fastapi-conventions`](../plugins/ai-toolkit-python-design/skills/python-fastapi-conventions/SKILL.md) | `ai-toolkit-python-design` | Apply FastAPI conventions for a REST service — thin routers, Depends-based injection, explicit response models, one pagination contract, problem+json error responses, URL conventions and lifespan-managed resources. |
| [`python-error-handling`](../plugins/ai-toolkit-python-build/skills/python-error-handling/SKILL.md) | `ai-toolkit-python-build` | Wire a clean error contract for a FastAPI service — a typed exception hierarchy, a static error-code and message catalogue, and ONE exception handler mapping every error to an RFC 7807 application/problem+json response. |
| [`python-input-validation`](../plugins/ai-toolkit-python-build/skills/python-input-validation/SKILL.md) | `ai-toolkit-python-build` | Implement all input validation in a Python service with pydantic v2 — Field constraints and validated types for per-field rules, model validators for cross-field rules, injectable rule objects for rules that need data or collaborators, custom messages, and a single validation layer. |
| [`python-persistence`](../plugins/ai-toolkit-python-build/skills/python-persistence/SKILL.md) | `ai-toolkit-python-build` | Wire the persistence layer of a Python service with SQLAlchemy 2.0 (typed Mapped models, async sessions) and Alembic migrations — repository per aggregate behind a Protocol, a single transaction/unit-of-work boundary, optimistic locking, and ORM models that never leak past the repository. |
| [`python-integration-tests`](../plugins/ai-toolkit-python-quality/skills/python-integration-tests/SKILL.md) | `ai-toolkit-python-quality` | Test a Python service against real infrastructure with testcontainers-python (PostgreSQL, Redis, Kafka, ...) and strict pytest-marker segregation between unit and integration suites, including Alembic migration checks and full-app API tests. |
| [`python-static-analysis`](../plugins/ai-toolkit-python-quality/skills/python-static-analysis/SKILL.md) | `ai-toolkit-python-quality` | Mechanically enforce style and catch bug classes in Python — ruff (lint + format), mypy --strict, pre-commit hooks and one pyproject.toml configuration, all wired so any violation breaks the build and cannot be skipped. |
| [`python-unit-tests`](../plugins/ai-toolkit-python-quality/skills/python-unit-tests/SKILL.md) | `ai-toolkit-python-quality` | Write meaningful pytest unit tests for Python services — positive, negative and edge cases, `method_condition_expectedResult` naming, fixtures, hand-written fakes at the boundary instead of mocking the class under test, parametrize for tables, and a coverage threshold that fails the build. |
| [`python-ci`](../plugins/ai-toolkit-python-ops/skills/python-ci/SKILL.md) | `ai-toolkit-python-ops` | Generate the Continuous Integration setup for a Python 3.12 service — a GitHub Actions workflow using uv with dependency caching and separate lint, type, unit and integration gates, plus a multi-stage, non-root, reproducible Dockerfile. |
| [`python-observability`](../plugins/ai-toolkit-python-ops/skills/python-observability/SKILL.md) | `ai-toolkit-python-ops` | Wire the three observability pillars into a Python/FastAPI service — structlog JSON logs with contextvars correlation IDs, OpenTelemetry distributed traces, and prometheus-client metrics with low-cardinality labels. |

## React Native (draft)

Language pilot — see [`LANGUAGE_CONTRACT.md`](./LANGUAGE_CONTRACT.md). Grouped by phase plugin.

| Skill | Plugin | Purpose |
| --- | --- | --- |
| [`react-native-code-structure`](../plugins/ai-toolkit-react-native-design/skills/react-native-code-structure/SKILL.md) | `ai-toolkit-react-native-design` | Apply the canonical React Native feature-based folder layout, TypeScript strict config, path aliases, dependency direction and naming (screens, components, hooks, services, api) when creating or refactoring an app. |
| [`react-native-state-and-data`](../plugins/ai-toolkit-react-native-design/skills/react-native-state-and-data/SKILL.md) | `ai-toolkit-react-native-design` | Apply the canonical data layer for React Native, with server state in TanStack Query behind a single api-client layer, client state in Zustand, query-key conventions, optimistic updates and an offline/retry stance. |
| [`react-native-error-handling`](../plugins/ai-toolkit-react-native-build/skills/react-native-error-handling/SKILL.md) | `ai-toolkit-react-native-build` | Wire a clean error contract for a React Native app, with a typed AppError hierarchy, a message catalogue, API-error-to-AppError mapping in exactly one place, error boundaries and a reporting hook. |
| [`react-native-input-validation`](../plugins/ai-toolkit-react-native-build/skills/react-native-input-validation/SKILL.md) | `ai-toolkit-react-native-build` | Implement all input validation in a React Native app with zod schemas in a validation layer, react-hook-form integration, cross-field rules and schemas shared with API types. |
| [`react-native-security`](../plugins/ai-toolkit-react-native-build/skills/react-native-security/SKILL.md) | `ai-toolkit-react-native-build` | Apply mobile security baselines for a React Native app, with secure token storage in Keychain/Keystore, no secrets in the JS bundle, deep-link and input validation, a TLS and pinning stance, and logging without PII. Use when storing credentials, handling deep links, adding config or keys, or adding logs. |
| [`react-native-e2e-tests`](../plugins/ai-toolkit-react-native-quality/skills/react-native-e2e-tests/SKILL.md) | `ai-toolkit-react-native-quality` | Write Maestro end-to-end flows for a React Native app with stable test IDs, deterministic test data, and a clear split between what belongs in E2E and in unit tests. |
| [`react-native-static-analysis`](../plugins/ai-toolkit-react-native-quality/skills/react-native-static-analysis/SKILL.md) | `ai-toolkit-react-native-quality` | Mechanically enforce style and catch bug classes in a React Native repo with TypeScript strict, ESLint flat config, Prettier, boundary rules, lint-staged and husky, all breaking the build in CI. Use when bootstrapping a repo, changing lint/tsc config, or when a violation appears. |
| [`react-native-unit-tests`](../plugins/ai-toolkit-react-native-quality/skills/react-native-unit-tests/SKILL.md) | `ai-toolkit-react-native-quality` | Write meaningful Jest + React Native Testing Library unit tests for components, hooks, schemas and mappers, with behaviour-focused queries, MSW for network, fakes over mocks, positive/negative/edge cases and a coverage threshold. |
| [`react-native-ci`](../plugins/ai-toolkit-react-native-ops/skills/react-native-ci/SKILL.md) | `ai-toolkit-react-native-ops` | Generate the GitHub Actions CI/CD setup for a React Native app, with cached installs, required lint/type/test gates, EAS Build or Fastlane builds, versioning and build numbers, and an OTA update stance. |
| [`react-native-observability`](../plugins/ai-toolkit-react-native-ops/skills/react-native-observability/SKILL.md) | `ai-toolkit-react-native-ops` | Wire observability into a React Native app with Sentry crash and performance monitoring, structured logging, analytics behind an interface, PII scrubbing and release health. |

## Extension points (where to plug in your own bindings)

The skills deliberately expose **SPIs and configuration knobs** instead
of hard-coding any environment-specific dependency. You can
add wrappers / starters in your own codebase that fill these in without modifying the
catalogue:

| Extension point | Typical binding in your organization |
| --- | --- |
| Spring Boot parent + plain dependencies | An organization-managed BOM and curated starters |
| Vanilla Jenkins declarative pipeline | A one-line call to a private shared library that runs build / sign / scan / push |
| Plain image registry placeholder | Organization registry + image-pull secret + signed-image policy |
| `ResponseEntityExceptionHandler` base class | An organization-specific advice base that adds trace IDs, request URIs, and standardized error codes |
| `CallerContextResolver` SPI | A resolver that reads the organization's custom authentication token shape |
| `ResourceAuthorizationSource` SPI | A client to the organization's authorization / search service |
| Generic `*Client` template | Pre-wired clients for in-house file storage, search, analytics, etc. |

## Maintainer references

| Resource | Purpose |
| --- | --- |
| [`./BACKEND_GUILD.md`](./BACKEND_GUILD.md) | Curated MUST / SHOULD / MAY adoption matrix + apply-order + task-driven recipes + non-negotiables for code review. |
| [`./REGISTRY.md`](./REGISTRY.md) | Machine-readable index of every skill (counts, templates indicator). |
| [`./AUTHORING.md`](./AUTHORING.md) | SKILL.md authoring contract — frontmatter rules, required sections, placeholder syntax, checklist. |
| [`./validate-skills.sh`](../tools/validate-skills.sh) | CI-friendly linter — fails on missing frontmatter, mismatched folder/`name`, broken template links, missing registry entries. |

Run the validator before opening a PR that touches `plugins/*/skills/`:

```sh
bash tools/validate-skills.sh
```

## Release check (maintainers)

`prepare-for-publish.sh` is the maintainers' pre-release gate. It reads an optional, gitignored `.publication-blocklist`
(one substring per line, `#` for comments) and fails if a listed term appears in tracked content, file names, the git
identity for new commits or git history, and it also checks for junk files, attribution lines, secrets and unreachable
objects. Contributors rely on CI (`.github/workflows/ci.yml`) instead; `tools/validate-skills.sh` also applies the
blocklist to `docs/` and `plugins/` when the file exists.


# Backend Guild — Golden Path

This is the **curated bundle** that every backend service in this
organization should follow when an agent (or a human) generates code. It
filters the atomic skills in [`REGISTRY.md`](./REGISTRY.md) into a
**MUST / SHOULD / MAY** adoption matrix, an apply-order sequence, and
task-driven recipes.

> Code that does not satisfy the **MUST** column will not pass a Backend
> Guild PR review.

> **Scope.** The recipes and the 24 non-negotiables below are the **Java 21 / Spring Boot**
> golden path. The adoption matrix lists every skill in the marketplace — Java, the
> language-neutral workflow/docs/quality skills, and the Python / React Native drafts. For a
> non-Java project follow that language's `hooks/routing.md` and the Do/Don't lists of its
> `python-*` / `react-native-*` skills; the *principles* (LEGO bricks, one canonical pattern,
> validation layer, typed errors, no commit until asked, `completion-gate`) are identical.

## 1. Adoption matrix

<!-- BEGIN AUTO:matrix -->
### MUST — every service (48)

| Skill | One-line summary |
| --- | --- |
| [`context-maintenance`](../plugins/ai-toolkit-docs/skills/context-maintenance/SKILL.md) | Maintain project context documentation including architecture, standards, build plans, and progress tracking. |
| [`documentation-and-adr`](../plugins/ai-toolkit-docs/skills/documentation-and-adr/SKILL.md) | Ship documentation as code — README, CONTRIBUTING, ARCHITECTURE (C4 levels 1–3 in PlantUML / Structurizr), Architecture Decision Records (ADRs) under `docs/adr/. |
| [`data-privacy`](../plugins/ai-toolkit-java-build/skills/data-privacy/SKILL.md) | Handle PII (Personally Identifiable Information) and GDPR requirements in a Java microservice — field-level encryption, masking in logs, data retention/TTL, rig. |
| [`exception-handling`](../plugins/ai-toolkit-java-build/skills/exception-handling/SKILL.md) | Wire a clean error contract for a Spring Boot microservice — a typed domain exception hierarchy, a static ExceptionMessages catalogue, and a @RestControllerAdvi. |
| [`external-client`](../plugins/ai-toolkit-java-build/skills/external-client/SKILL.md) | Java / Spring Boot: Generate an SDK-style integration package for an external service (HTTP, gRPC, message broker, file store). |
| [`input-validation`](../plugins/ai-toolkit-java-build/skills/input-validation/SKILL.md) | The skill to APPLY when writing or changing any Spring Boot input validator — Jakarta Bean Validation (ConstraintValidator) for field/parameter rules and Spring. |
| [`permissions`](../plugins/ai-toolkit-java-build/skills/permissions/SKILL.md) | Wire authentication & authorization into a Spring Boot microservice using the Strategy + Handler pattern. |
| [`resilience-patterns`](../plugins/ai-toolkit-java-build/skills/resilience-patterns/SKILL.md) | Java / Spring Boot: Beyond simple retries — implement advanced stability patterns using Resilience4j (Bulkheads, Timeouts, Rate Limiters) and architectural stra. |
| [`security-hardening`](../plugins/ai-toolkit-java-build/skills/security-hardening/SKILL.md) | Cross-cutting security beyond authentication & authorization — input validation, OWASP Top 10 checklist tailored to Spring Boot, CORS, rate limiting, secret man. |
| [`api-design`](../plugins/ai-toolkit-java-design/skills/api-design/SKILL.md) | REST API design rules every Spring Boot service publishes — resource modelling, HTTP-verb semantics, status code catalogue, URL conventions, versioning (URI vs . |
| [`code-structure`](../plugins/ai-toolkit-java-design/skills/code-structure/SKILL.md) | Apply the canonical Java/Spring Boot package hierarchy and design patterns (Strategy + Registry, OncePerRequestFilter for metrics, Recorder pattern, Operation/S. |
| [`pattern-selection`](../plugins/ai-toolkit-java-design/skills/pattern-selection/SKILL.md) | Java / Spring Boot: choose the smallest pattern that fits the actual scale — scale-based decision tables for external clients, operations and layers, red flags . |
| [`pluggable-architecture`](../plugins/ai-toolkit-java-design/skills/pluggable-architecture/SKILL.md) | Java / Spring Boot: Treat every external technology integration (cache, database, metrics backend, message broker, object store, secret manager, identity provid. |
| [`spring-boot-conventions`](../plugins/ai-toolkit-java-design/skills/spring-boot-conventions/SKILL.md) | Standard Spring Boot 3 idioms every Java microservice should adopt — typed @ConfigurationProperties over @Value, profile management, conditional beans, JSR-380 . |
| [`testable-code-principles`](../plugins/ai-toolkit-java-design/skills/testable-code-principles/SKILL.md) | Java / Spring Boot: Foundational principles for writing testable code - LEGO Bricks (small, focused, self-explanatory components), SDK-like design (document thr. |
| [`cd`](../plugins/ai-toolkit-java-ops/skills/cd/SKILL.md) | Generate a vendor-neutral Helm chart to deploy a Java/Spring Boot microservice to Kubernetes, with hardened security context, liveness/readiness probes on Actua. |
| [`ci`](../plugins/ai-toolkit-java-ops/skills/ci/SKILL.md) | Generate the Continuous Integration setup (Jenkinsfile, Dockerfile, Maven build) for a generic Java 21 / Spring Boot microservice. |
| [`github-actions-ci`](../plugins/ai-toolkit-java-ops/skills/github-actions-ci/SKILL.md) | Java / Spring Boot: Alternative to the Jenkins-based `ci` skill — GitHub Actions workflows for build / test / image / release / dependency-scan. |
| [`graceful-shutdown`](../plugins/ai-toolkit-java-ops/skills/graceful-shutdown/SKILL.md) | Wire graceful shutdown into a Spring Boot service so Kubernetes pod terminations drain in-flight requests, async work, message consumers, and outbound clients w. |
| [`local-dev-experience`](../plugins/ai-toolkit-java-ops/skills/local-dev-experience/SKILL.md) | Java / Spring Boot: Make the inner loop reproducible in under 5 minutes — docker-compose for downstream dependencies, Makefile/Justfile commands,. |
| [`observability`](../plugins/ai-toolkit-java-ops/skills/observability/SKILL.md) | Wire the three observability pillars — metrics (Micrometer + Prometheus), structured JSON logs with MDC correlation IDs, and distributed traces (OpenTelemetry) . |
| [`request-metrics`](../plugins/ai-toolkit-java-ops/skills/request-metrics/SKILL.md) | Implement per-request domain metrics in a Spring Boot microservice with the Filter + Recorder + Parser pattern. |
| [`component-tests`](../plugins/ai-toolkit-java-quality/skills/component-tests/SKILL.md) | Generate Spring Boot component (slice) tests that boot the full application context with a dedicated test profile, replace external collaborators (HTTP clients,. |
| [`golden-path`](../plugins/ai-toolkit-java-quality/skills/golden-path/SKILL.md) | The Java / Spring Boot golden path — the apply-order of the skills and the 24 non-negotiables every diff must satisfy. |
| [`quality-review`](../plugins/ai-toolkit-java-quality/skills/quality-review/SKILL.md) | Java / Spring Boot: Run a SOLID / clean-code / testability / project-conventions review on a class, package, or pull request. |
| [`static-analysis`](../plugins/ai-toolkit-java-quality/skills/static-analysis/SKILL.md) | Java / Spring Boot: Mechanically enforce code style and catch bug classes — Spotless (formatter), SpotBugs (bug patterns), Error-Prone (compile-time bug pattern. |
| [`unit-tests`](../plugins/ai-toolkit-java-quality/skills/unit-tests/SKILL.md) | Generate meaningful, high-coverage JUnit 5 + Mockito unit tests for Spring Boot classes. |
| [`create-repo`](../plugins/ai-toolkit-java-scaffold/skills/create-repo/SKILL.md) | Human-in-the-loop scaffolder that creates a brand-new Java/Spring Boot microservice repository. |
| [`project-types`](../plugins/ai-toolkit-java-scaffold/skills/project-types/SKILL.md) | Java / Spring Boot: Meta-skill — picks the right combination of skills for the **kind** of project being created. |
| [`python-error-handling`](../plugins/ai-toolkit-python-build/skills/python-error-handling/SKILL.md) | Wire a clean error contract for a FastAPI service — a typed exception hierarchy, a static error-code and message catalogue, and ONE exception handler mapping ev. |
| [`python-input-validation`](../plugins/ai-toolkit-python-build/skills/python-input-validation/SKILL.md) | Implement all input validation in a Python service with pydantic v2 — Field constraints and validated types for per-field rules, model validators for cross-fiel. |
| [`python-code-structure`](../plugins/ai-toolkit-python-design/skills/python-code-structure/SKILL.md) | Apply the canonical Python 3. |
| [`python-fastapi-conventions`](../plugins/ai-toolkit-python-design/skills/python-fastapi-conventions/SKILL.md) | Apply FastAPI conventions for a REST service — thin routers, Depends-based injection, explicit response models, one pagination contract, problem+json error resp. |
| [`python-ci`](../plugins/ai-toolkit-python-ops/skills/python-ci/SKILL.md) | Generate the Continuous Integration setup for a Python 3. |
| [`python-static-analysis`](../plugins/ai-toolkit-python-quality/skills/python-static-analysis/SKILL.md) | Mechanically enforce style and catch bug classes in Python — ruff (lint + format), mypy --strict, pre-commit hooks and one pyproject. |
| [`python-unit-tests`](../plugins/ai-toolkit-python-quality/skills/python-unit-tests/SKILL.md) | Write meaningful pytest unit tests for Python services — positive, negative and edge cases, `method_condition_expectedResult` naming, fixtures, hand-written fak. |
| [`code-hygiene`](../plugins/ai-toolkit-quality/skills/code-hygiene/SKILL.md) | Keep a diff minimal and self-explanatory — no comments or docs that restate the code, no dead code, no speculative abstraction, no unrelated churn, and no redun. |
| [`completion-gate`](../plugins/ai-toolkit-quality/skills/completion-gate/SKILL.md) | The definition of done for any implementation task — never commit or push until the user asks, then before reporting done prove the build passes, all tests pass. |
| [`react-native-error-handling`](../plugins/ai-toolkit-react-native-build/skills/react-native-error-handling/SKILL.md) | Wire a clean error contract for a React Native app, with a typed AppError hierarchy, a message catalogue, API-error-to-AppError mapping in exactly one place, er. |
| [`react-native-input-validation`](../plugins/ai-toolkit-react-native-build/skills/react-native-input-validation/SKILL.md) | Implement all input validation in a React Native app with zod schemas in a validation layer, react-hook-form integration, cross-field rules and schemas shared w. |
| [`react-native-security`](../plugins/ai-toolkit-react-native-build/skills/react-native-security/SKILL.md) | Apply mobile security baselines for a React Native app, with secure token storage in Keychain/Keystore, no secrets in the JS bundle, deep-link and input validat. |
| [`react-native-code-structure`](../plugins/ai-toolkit-react-native-design/skills/react-native-code-structure/SKILL.md) | Apply the canonical React Native feature-based folder layout, TypeScript strict config, path aliases, dependency direction and naming (screens, components, hook. |
| [`react-native-state-and-data`](../plugins/ai-toolkit-react-native-design/skills/react-native-state-and-data/SKILL.md) | Apply the canonical data layer for React Native, with server state in TanStack Query behind a single api-client layer, client state in Zustand, query-key conven. |
| [`react-native-ci`](../plugins/ai-toolkit-react-native-ops/skills/react-native-ci/SKILL.md) | Generate the GitHub Actions CI/CD setup for a React Native app, with cached installs, required lint/type/test gates, EAS Build or Fastlane builds, versioning an. |
| [`react-native-static-analysis`](../plugins/ai-toolkit-react-native-quality/skills/react-native-static-analysis/SKILL.md) | Mechanically enforce style and catch bug classes in a React Native repo with TypeScript strict, ESLint flat config, Prettier, boundary rules, lint-staged and hu. |
| [`react-native-unit-tests`](../plugins/ai-toolkit-react-native-quality/skills/react-native-unit-tests/SKILL.md) | Write meaningful Jest + React Native Testing Library unit tests for components, hooks, schemas and mappers, with behaviour-focused queries, MSW for network, fak. |
| [`git-commit-conventions`](../plugins/ai-toolkit-workflow/skills/git-commit-conventions/SKILL.md) | Write and sequence git commits so history stays reviewable and bisectable — Conventional Commit prefixes (feat, fix, docs, style, refactor, perf, test, build, c. |
| [`release-versioning`](../plugins/ai-toolkit-workflow/skills/release-versioning/SKILL.md) | Standardize the release lifecycle — Conventional Commits, Semantic Versioning, automated CHANGELOG generation (release-please or semantic-release), git tag = ar. |

### SHOULD — when the service has the feature (22)

| Skill | One-line summary |
| --- | --- |
| [`uml-diagram`](../plugins/ai-toolkit-docs/skills/uml-diagram/SKILL.md) | Create and maintain UML diagrams using Mermaid to visualize system architecture, component relationships, and interaction flows. |
| [`messaging`](../plugins/ai-toolkit-java-build/skills/messaging/SKILL.md) | Wire async messaging (Kafka or RabbitMQ) into a Spring Boot service with the canonical patterns — idempotent consumer, transactional outbox for producer-side at. |
| [`persistence`](../plugins/ai-toolkit-java-build/skills/persistence/SKILL.md) | Wire the persistence layer of a Spring Boot service — Spring Data JPA repositories, JPA entities (records vs classes), Flyway migrations, transaction boundaries. |
| [`rate-limiting`](../plugins/ai-toolkit-java-build/skills/rate-limiting/SKILL.md) | Java / Spring Boot: Protect the service from abuse and ensure fair usage using rate-limiting strategies. |
| [`sdk-publishing`](../plugins/ai-toolkit-java-build/skills/sdk-publishing/SKILL.md) | Producer-side of the lego-brick principle. |
| [`async-api-patterns`](../plugins/ai-toolkit-java-design/skills/async-api-patterns/SKILL.md) | Java / Spring Boot: Handle long-running operations (> 2s) in a RESTful way. |
| [`domain-modeling`](../plugins/ai-toolkit-java-design/skills/domain-modeling/SKILL.md) | Tactical Domain-Driven Design vocabulary every Java microservice should adopt — Bounded Context, Aggregate Root, Entity, Value Object, Domain Event, Domain Serv. |
| [`feature-flags`](../plugins/ai-toolkit-java-design/skills/feature-flags/SKILL.md) | Java / Spring Boot: Implement feature toggles (flags) to decouple deployment from release. |
| [`openapi-first-codegen`](../plugins/ai-toolkit-java-design/skills/openapi-first-codegen/SKILL.md) | Drive controllers and DTOs from an OpenAPI 3 contract at the repo root (`api. |
| [`response-layout`](../plugins/ai-toolkit-java-design/skills/response-layout/SKILL.md) | Wire layout query parameter support (?layout=summary/detailed/full) into a Spring Boot REST endpoint using the Strategy + Handler + Registry pattern. |
| [`response-mapper`](../plugins/ai-toolkit-java-design/skills/response-mapper/SKILL.md) | Wire API versioning and response projection mapping into a Spring Boot REST API using the Strategy + Handler + Registry pattern. |
| [`health-indicator`](../plugins/ai-toolkit-java-ops/skills/health-indicator/SKILL.md) | Interactive (HITL) skill that adds a Spring Boot Actuator readiness HealthIndicator for a downstream dependency. |
| [`adapter-contract-tests`](../plugins/ai-toolkit-java-quality/skills/adapter-contract-tests/SKILL.md) | Java / Spring Boot: Prove the lego-brick contract — write one shared, vendor-neutral abstract test suite (a TCK) per port interface, then run it against EVERY a. |
| [`integration-tests`](../plugins/ai-toolkit-java-quality/skills/integration-tests/SKILL.md) | Drive a Spring Boot microservice against real downstream dependencies (DB, broker, S3-compatible object store, mocked HTTP) using Testcontainers, with strict Su. |
| [`python-persistence`](../plugins/ai-toolkit-python-build/skills/python-persistence/SKILL.md) | Wire the persistence layer of a Python service with SQLAlchemy 2. |
| [`python-observability`](../plugins/ai-toolkit-python-ops/skills/python-observability/SKILL.md) | Wire the three observability pillars into a Python/FastAPI service — structlog JSON logs with contextvars correlation IDs, OpenTelemetry distributed traces, and. |
| [`python-integration-tests`](../plugins/ai-toolkit-python-quality/skills/python-integration-tests/SKILL.md) | Test a Python service against real infrastructure with testcontainers-python (PostgreSQL, Redis, Kafka,. |
| [`sonar-quality-gate`](../plugins/ai-toolkit-quality/skills/sonar-quality-gate/SKILL.md) | Run the project's SonarQube/SonarCloud analysis on your change and drive the new-code quality gate to green — bugs, vulnerabilities, code smells, security hotsp. |
| [`react-native-observability`](../plugins/ai-toolkit-react-native-ops/skills/react-native-observability/SKILL.md) | Wire observability into a React Native app with Sentry crash and performance monitoring, structured logging, analytics behind an interface, PII scrubbing and re. |
| [`react-native-e2e-tests`](../plugins/ai-toolkit-react-native-quality/skills/react-native-e2e-tests/SKILL.md) | Write Maestro end-to-end flows for a React Native app with stable test IDs, deterministic test data, and a clear split between what belongs in E2E and in unit t. |
| [`parallel-delegation`](../plugins/ai-toolkit-workflow/skills/parallel-delegation/SKILL.md) | Decide when and how to hand work to subagents so independent pieces run in parallel without conflicts — what is safe to delegate, how to brief a subagent that c. |
| [`pr-description`](../plugins/ai-toolkit-workflow/skills/pr-description/SKILL.md) | Write and update pull request descriptions on Bitbucket Server so reviewers immediately understand what changed, why, and how to verify it — structured sections. |

### FOUNDATIONAL — patterns other skills build on (2)

| Skill | One-line summary |
| --- | --- |
| [`validation-pattern`](../plugins/ai-toolkit-java-build/skills/validation-pattern/SKILL.md) | Background theory and rationale for input validation in Spring Boot microservices — Jakarta Bean Validation (ConstraintValidator) for field/parameter-level rule. |
| [`strategy-registry-pattern`](../plugins/ai-toolkit-java-design/skills/strategy-registry-pattern/SKILL.md) | Foundational architectural pattern for implementing pluggable, extensible behavior in Spring Boot microservices. |

### MAY — useful but optional (1)

| Skill | One-line summary |
| --- | --- |
| [`refactoring-playbook`](../plugins/ai-toolkit-java-quality/skills/refactoring-playbook/SKILL.md) | Java / Spring Boot: Step-by-step migrations from common anti-patterns to the canonical patterns shipped by the other skills — `@Value` → `@ConfigurationProperti. |

<!-- END AUTO:matrix -->

## 1b. Dependency graph (auto)

<!-- BEGIN AUTO:graph -->
```mermaid
graph LR
  documentation_and_adr --> context_maintenance
  uml_diagram --> documentation_and_adr
  persistence --> data_privacy
  observability --> data_privacy
  pluggable_architecture --> data_privacy
  code_structure --> exception_handling
  code_structure --> external_client
  observability --> external_client
  pluggable_architecture --> external_client
  code_structure --> input_validation
  exception_handling --> input_validation
  spring_boot_conventions --> input_validation
  validation_pattern --> input_validation
  code_structure --> messaging
  observability --> messaging
  pluggable_architecture --> messaging
  code_structure --> permissions
  exception_handling --> permissions
  strategy_registry_pattern --> permissions
  code_structure --> persistence
  pluggable_architecture --> persistence
  observability --> rate_limiting
  external_client --> rate_limiting
  pluggable_architecture --> rate_limiting
  external_client --> resilience_patterns
  release_versioning --> sdk_publishing
  static_analysis --> sdk_publishing
  permissions --> security_hardening
  code_structure --> validation_pattern
  spring_boot_conventions --> validation_pattern
  code_structure --> api_design
  code_structure --> async_api_patterns
  testable_code_principles --> code_structure
  code_structure --> domain_modeling
  code_structure --> feature_flags
  pluggable_architecture --> feature_flags
  api_design --> openapi_first_codegen
  code_structure --> pattern_selection
  code_structure --> pluggable_architecture
  spring_boot_conventions --> pluggable_architecture
  code_structure --> response_layout
  spring_boot_conventions --> response_layout
  strategy_registry_pattern --> response_layout
  code_structure --> response_mapper
  spring_boot_conventions --> response_mapper
  strategy_registry_pattern --> response_mapper
  code_structure --> spring_boot_conventions
  code_structure --> strategy_registry_pattern
  spring_boot_conventions --> strategy_registry_pattern
  ci --> cd
  static_analysis --> ci
  static_analysis --> github_actions_ci
  cd --> health_indicator
  observability --> health_indicator
  code_structure --> observability
  pluggable_architecture --> observability
  code_structure --> request_metrics
  observability --> request_metrics
  spring_boot_conventions --> request_metrics
  strategy_registry_pattern --> request_metrics
  pluggable_architecture --> adapter_contract_tests
  unit_tests --> adapter_contract_tests
  unit_tests --> component_tests
  code_structure --> golden_path
  quality_review --> golden_path
  component_tests --> integration_tests
  unit_tests --> quality_review
  static_analysis --> quality_review
  testable_code_principles --> quality_review
  quality_review --> refactoring_playbook
  code_structure --> unit_tests
  testable_code_principles --> unit_tests
  project_types --> create_repo
  code_structure --> create_repo
  ci --> create_repo
  cd --> create_repo
  local_dev_experience --> create_repo
  python_code_structure --> python_error_handling
  python_code_structure --> python_input_validation
  python_error_handling --> python_input_validation
  python_code_structure --> python_persistence
  python_error_handling --> python_persistence
  python_code_structure --> python_fastapi_conventions
  python_static_analysis --> python_ci
  python_unit_tests --> python_ci
  python_code_structure --> python_observability
  python_unit_tests --> python_integration_tests
  python_persistence --> python_integration_tests
  python_code_structure --> python_static_analysis
  python_code_structure --> python_unit_tests
  completion_gate --> code_hygiene
  code_hygiene --> completion_gate
  sonar_quality_gate --> completion_gate
  completion_gate --> sonar_quality_gate
  react_native_code_structure --> react_native_error_handling
  react_native_state_and_data --> react_native_error_handling
  react_native_code_structure --> react_native_input_validation
  react_native_error_handling --> react_native_input_validation
  react_native_code_structure --> react_native_security
  react_native_input_validation --> react_native_security
  react_native_state_and_data --> react_native_code_structure
  react_native_code_structure --> react_native_state_and_data
  react_native_static_analysis --> react_native_ci
  react_native_unit_tests --> react_native_ci
  react_native_error_handling --> react_native_observability
  react_native_security --> react_native_observability
  react_native_ci --> react_native_observability
  react_native_unit_tests --> react_native_e2e_tests
  react_native_code_structure --> react_native_e2e_tests
  react_native_code_structure --> react_native_static_analysis
  react_native_code_structure --> react_native_unit_tests
  react_native_state_and_data --> react_native_unit_tests
  react_native_error_handling --> react_native_unit_tests
  git_commit_conventions --> pr_description
  git_commit_conventions --> release_versioning
```
<!-- END AUTO:graph -->


## 2. Adoption sequence (apply-order)

```text
project-types                            ← pick the shape
        │
        ▼
create-repo (HITL)                       ← generates skeleton, asks 16 questions
        │
        ├─► code-structure               ← packages, base classes
        ├─► spring-boot-conventions      ← config, profiles, async, scheduled
        ├─► api-design  ─►  openapi-first-codegen (optional)
        ├─► exception-handling
        ├─► permissions                  ← SPIs only; concrete resolver is yours to supply
        ├─► external-client              ← one sub-package per downstream
        ├─► persistence (Flyway OR Liquibase)
        ├─► messaging                    ← if event-driven
        ├─► health-indicator (HITL, repeat per dep)
        ├─► observability
        ├─► security-hardening
        ├─► graceful-shutdown
        │
        ├─► unit-tests + component-tests + integration-tests
        ├─► static-analysis              ← build-gated
        ├─► quality-review               ← pre-PR
        │
        ├─► ci  OR  github-actions-ci    ← pick one
        ├─► cd                           ← Helm chart
        ├─► local-dev-experience
        │
        ├─► release-versioning
        ├─► documentation-and-adr  + uml-diagram
        └─► context-maintenance          ← every time architecture moves
```

## 3. Task-driven agent recipes

Each recipe lists **only** the skills that materially constrain the change.
An agent should read the listed skills (in order) before producing a diff.

### 3.1 New repository

`project-types` → `create-repo` → (all MUST) → optional SHOULD skills the
shape demands.

### 3.2 New HTTP endpoint

`api-design` (incl. §6b for multipart) → `openapi-first-codegen` (if used)
→ `code-structure` → `permissions` → `exception-handling` → `unit-tests` +
`component-tests`.

### 3.3 New outbound dependency

`external-client` → `health-indicator` (HITL) → `observability` →
`integration-tests` (if it has real semantics) → `security-hardening` (auth
/ secrets).

### 3.4 New entity / schema change

`persistence` (right migration tool) → `domain-modeling` (if aggregate
boundaries change) → `integration-tests` → migration test on empty DB.

### 3.5 New Kafka consumer

`messaging` → `code-structure` (consumer sub-package) → `observability`
(consumer lag SLI) → `integration-tests` (Testcontainers Kafka) →
`graceful-shutdown` (consumer drain).

### 3.6 New scheduled job

`spring-boot-conventions` §7b → `observability` (`scheduled.task.duration`
timer) → `unit-tests` (idempotency test) → `graceful-shutdown` (interrupt-
aware sleep).

### 3.7 Refactor / pay down debt

`refactoring-playbook` → `quality-review` → re-run `unit-tests` +
`static-analysis` and verify mutation score did not regress.

### 3.8 Pre-PR check (every change)

`quality-review` checklist + `bash tools/validate-skills.sh` if
`plugins/*/skills/` was touched + ensure `static-analysis` build passes locally.

### 3.9 New external technology integration (cache, DB dialect, metrics backend, broker, …)

`pluggable-architecture` (define the `spi/` port → `adapter/<vendor>/`
implementations → config-driven selection with a `@ConditionalOnMissingBean`
default) → `adapter-contract-tests` (one TCK per port, every adapter passes
it) → `observability` (per-provider metrics/logs) → `integration-tests`
(Testcontainers for real-backend adapters). Confirm a provider swap needs
**only** a property change.

### 3.10 New validation rule

`input-validation` (decide Jakarta `@Constraint` vs Spring `Validator` →
create rule bean in `rule/` → create validator in `validator/` → register in
`ValidationConfig` or add `@Validated` to controller) → `unit-tests` (rule
bean in isolation, validator with mocked `ConstraintValidatorContext`) →
`component-tests` (end-to-end 400 `ProblemDetail` path).

### 3.11 New downstream microservice integration

**CRITICAL - HITL CHECKPOINT**: Before applying pattern, ASK developer:
- How many API endpoints/methods needed NOW? (1-4, 5-9, 10+)
- Is this simple REST CRUD or complex SDK integration?
- Expected growth in next 6 months?

**Pattern Selection** (see `external-client` §0):
- **1-4 simple endpoints** → `external-client` Pattern 1 (Simple Wrapper: 3 files)
- **5-9 endpoints** → `external-client` Pattern 2 (Lite Client: 5 files)
- **10+ OR complex DSL** → `external-client` Pattern 3 (Full 5-Layer: 7-9 files)

Then continue with: `exception-handling` (domain exception for non-2xx) → `health-indicator`
(readiness probe for the new dependency) → `resilience-patterns` (circuit
breaker + retry) → `request-metrics` (add a recorder if the call is an
endpoint the team wants to meter) → `unit-tests` (every layer) →
`integration-tests` (WireMock against the real HTTP boundary).

**Default Rule**: When uncertain, start with Pattern 1. Refactor to Pattern 2/3 when complexity justifies it.

### 3.12 New domain endpoint metric

`request-metrics` (add `METRIC_<NAME>` constant → URI pattern in
`MonitoringConfig` → `<UseCase>MetricsRecorder` → any new `<Concept>Parser`
if a new tag is needed) → `unit-tests` (recorder + parser) → `observability`
(alert rule / dashboard panel if SLO is involved).

## 4. Guild non-negotiables (24)

These are the rules the guild enforces during PR review. Every agent
producing code must validate the diff against this list before returning.

1. **Package layout** matches `code-structure` exactly.
2. **Config** is `@ConfigurationProperties` (record), never `@Value` for
   grouped properties (`spring-boot-conventions` §1).
3. **Controllers contain no business logic**; they call a `*Service` or a
   `*Operation` (`code-structure`).
4. **Exceptions** extend the project hierarchy and carry an
   `ExceptionMessages` code (`exception-handling`).
5. **Authorization** goes through `PermissionsHandler`, never inline
   `if (principal.isAdmin)` (`permissions`).
6. **Outbound HTTP** goes through an `*Client` in its own sub-package —
   never raw `WebClient` / `RestClient` calls in a service.
   **Pattern complexity must match integration scale** (`external-client` §0):
   - Simple CRUD (1-4 endpoints) → Simple Wrapper pattern
   - Medium complexity (5-9 endpoints) → Lite Client pattern  
   - Complex SDK (10+ endpoints OR complex DSL) → Full 5-Layer pattern
   **HITL required**: Ask developer about scale before choosing pattern.
7. **Transactions** live in the service layer, `readOnly = true` for
   queries (`persistence` §4).
8. **`@Async` and `@Scheduled`** use a named `TaskExecutor` and a property-
   driven interval respectively (`spring-boot-conventions` §7, §7b).
9. **Caching** declares the provider, name, key, and TTL explicitly
   (`spring-boot-conventions` §8).
10. **Messaging consumers** are idempotent and have a DLQ wired
    (`messaging`).
11. **Logs** are JSON with MDC correlation IDs; no `e.printStackTrace()`
    (`observability`).
12. **Tests**: PIT mutation score ≥ 75 %; no `@MockBean` on the class
    under test; right-boundary mocking (`unit-tests`, `quality-review`).
13. **Static analysis** is non-skippable in the Maven build
    (`static-analysis`).
14. **Generated sources** under `target/generated-sources/**` are excluded
    from coverage, Spotless, SpotBugs, NullAway, ArchUnit
    (`openapi-first-codegen`).
15. **URL conventions**: plural nouns, kebab-case, version in path,
    `application/problem+json` for errors (`api-design`).
16. **Secrets** never appear in `application.yaml` or in commit history
    (`security-hardening`).
17. **Graceful shutdown** is enabled and exercised by a component test
    (`graceful-shutdown`).
18. **Releases** use Conventional Commits; CHANGELOG is automated
    (`release-versioning`).
19. **`context/` documentation** is updated in the same PR as the code
    change it describes (`context-maintenance`).
20. **External technology is behind a port.** Any integration with an
    external tool (cache, DB dialect, metrics backend, broker, object
    store, secret manager, identity provider, …) is consumed through a
    project-owned `spi/` port; the vendor SDK is imported **only** inside
    `adapter/<vendor>/`; selection/composition is config-driven in
    `config/` with a `@ConditionalOnMissingBean` safe default. No vendor
    type leaks into `spi/`, `service/`, `operation/`, or `controller/`
    (`pluggable-architecture`, ArchUnit-enforced).
21. **Every adapter passes the shared port TCK.** Each port has one
    abstract contract test; every adapter (including the composite)
    subclasses it and passes identical assertions, and a build check fails
    when an `*Adapter` has no matching `*ContractTest`
    (`adapter-contract-tests`).
22. **Input validation lives in the validation layer — never inline.**
    Parameter/field rules use Jakarta `@Constraint` + `ConstraintValidator`;
    object/cross-field rules use Spring `Validator` + `@InitBinder`.
    Domain rule logic is extracted into `rule/` beans. The controller class
    carries `@Validated`; never write `if (x == null) throw new
    BadRequestException(...)` in a controller, operation, or service
    (`input-validation`).
23. **Every external downstream is wrapped in a `client/<dep>/` sub-package.**
    **Pattern choice depends on scale** — ask developer before applying:
    - 1-4 simple CRUD endpoints → Simple Wrapper (3 files)
    - 5-9 endpoints with complexity → Lite Client (5 files)
    - 10+ endpoints OR complex DSL → Full 5-Layer (7-9 files)
    See `external-client` §0 decision tree. Default: start simple, add layers when needed.
    Callers depend only on `*Service`; `WebClient`, `Mono`, `Flux`, and remote
    DTOs never escape the package. `exchangeToMono` + `handleResponse` handles
    all non-2xx. Filter map, request building, response parsing, and boolean
    response checks each live in their own dedicated class
    (`external-client`).
24. **Domain endpoint metrics use the Filter → Recorder → Parser pattern.**
    `MetricsFilter` measures every request in `try/finally`; `MonitoringConfig`
    maps URI regexes to metric names; `MetricsRecorderRegistry` routes to a
    `MetricsRecorder`; parsers extract tags. A new metric = one new recorder +
    one `MonitoringConfig` entry. Parsers never return `null` or blank
    (`request-metrics`).

## 5. Pre-flight checklist — first PR of a new service

- [ ] `mvn -q verify` passes locally and in CI.
- [ ] Mutation score ≥ 75 % on the touched packages.
- [ ] Liveness + readiness probes return 200 against a real run.
- [ ] Docker image runs as **non-root** and starts on a clean machine.
- [ ] Helm chart `helm lint` clean.
- [ ] `README.md` answers: what does it do, how do I run it, how do I
      observe it, who owns it.
- [ ] ADR-0001 (initial architecture) merged under `docs/adr/`.
- [ ] `context/` folder populated; `context-maintenance` skill applied.
- [ ] `bash tools/validate-skills.sh` clean (if you touched `plugins/*/skills/`).

## 6. Change-control for this document

This file is a contract between the guild and code-generating agents.
Loosening any of the **24 non-negotiables** requires:

1. An ADR proposing the change under `docs/adr/`.
2. Approval from the architect group responsible for the catalogue.
3. A matching update to [`REGISTRY.md`](./REGISTRY.md) and the affected
   `SKILL.md`.
4. `bash tools/validate-skills.sh` passing on the same PR.
5. A guild vote when the change weakens an enforcement (e.g. lowering the
   mutation-score threshold).


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
| [`documentation-and-adr`](../plugins/ai-toolkit-docs/skills/documentation-and-adr/SKILL.md) | Docs as code — README, CONTRIBUTING, ARCHITECTURE (C4 in PlantUML/Structurizr), ADRs under docs/adr/, generated class and sequence diagrams. |
| [`data-privacy`](../plugins/ai-toolkit-java-build/skills/data-privacy/SKILL.md) | Handle PII (Personally Identifiable Information) and GDPR requirements in a Java microservice — field-level encryption, masking in logs, data retention/TTL, rig. |
| [`exception-handling`](../plugins/ai-toolkit-java-build/skills/exception-handling/SKILL.md) | Java / Spring Boot error contract — typed domain exception hierarchy, static ExceptionMessages catalogue, @RestControllerAdvice mapping each exception to an RFC. |
| [`external-client`](../plugins/ai-toolkit-java-build/skills/external-client/SKILL.md) | Java / Spring Boot: SDK-style package for a downstream service (HTTP, gRPC, broker, file store) — Service facade, CoreService, thin Client, request builders, re. |
| [`input-validation`](../plugins/ai-toolkit-java-build/skills/input-validation/SKILL.md) | Java / Spring Boot input validation — Jakarta ConstraintValidator for field/parameter rules, Spring Validator for cross-field rules, custom annotations, injecte. |
| [`permissions`](../plugins/ai-toolkit-java-build/skills/permissions/SKILL.md) | Java / Spring Boot authorization via Strategy + Handler — a PermissionsHandler dispatches by caller context (user, service account, external system) to pluggabl. |
| [`resilience-patterns`](../plugins/ai-toolkit-java-build/skills/resilience-patterns/SKILL.md) | Java / Spring Boot stability with Resilience4j — timeouts, bulkheads, circuit breakers, fallbacks, fail-fast. |
| [`security-hardening`](../plugins/ai-toolkit-java-build/skills/security-hardening/SKILL.md) | Java / Spring Boot security beyond authn/authz — OWASP Top 10 checklist, CORS, security headers, secret management, dependency scanning, image signing. |
| [`api-design`](../plugins/ai-toolkit-java-design/skills/api-design/SKILL.md) | Java / Spring Boot REST API design — resources and URLs, HTTP verbs, status codes, versioning, pagination/filtering/sorting, deprecation headers, RFC 7807 error. |
| [`code-structure`](../plugins/ai-toolkit-java-design/skills/code-structure/SKILL.md) | Java / Spring Boot package hierarchy and layering — controller/operation/service, filter + recorder; every class a small, testable LEGO brick. |
| [`pattern-selection`](../plugins/ai-toolkit-java-design/skills/pattern-selection/SKILL.md) | Java / Spring Boot: choose the smallest pattern that fits the actual scale — decision tables for clients, operations and layers, over-engineering red flags. |
| [`pluggable-architecture`](../plugins/ai-toolkit-java-design/skills/pluggable-architecture/SKILL.md) | Java / Spring Boot ports and adapters — every external technology (cache, DB, broker, metrics, object store, secrets, identity) behind a port, with adapters cho. |
| [`spring-boot-conventions`](../plugins/ai-toolkit-java-design/skills/spring-boot-conventions/SKILL.md) | Java / Spring Boot 3 idioms — @ConfigurationProperties over @Value, profiles, conditional beans, @Async with named executors, caching, pagination, idempotency, . |
| [`testable-code-principles`](../plugins/ai-toolkit-java-design/skills/testable-code-principles/SKILL.md) | Java / Spring Boot testability principles — small LEGO-brick classes, names over comments, SOLID mapped to testing, no static methods, global state or hidden si. |
| [`cd`](../plugins/ai-toolkit-java-ops/skills/cd/SKILL.md) | Java / Spring Boot Helm chart for Kubernetes — hardened security context, Actuator liveness/readiness probes, HPA, Prometheus ServiceMonitor, credentials Secret. |
| [`ci`](../plugins/ai-toolkit-java-ops/skills/ci/SKILL.md) | Java 21 / Spring Boot CI with Jenkins — declarative Jenkinsfile, multi-stage Dockerfile, Maven build. |
| [`github-actions-ci`](../plugins/ai-toolkit-java-ops/skills/github-actions-ci/SKILL.md) | Java / Spring Boot CI on GitHub Actions — build, test, image, release and dependency-scan workflows on GitHub-hosted runners. |
| [`graceful-shutdown`](../plugins/ai-toolkit-java-ops/skills/graceful-shutdown/SKILL.md) | Java / Spring Boot graceful shutdown — drain in-flight requests, async work, consumers and clients on Kubernetes pod termination. |
| [`local-dev-experience`](../plugins/ai-toolkit-java-ops/skills/local-dev-experience/SKILL.md) | Java / Spring Boot inner loop in under 5 minutes — docker-compose for dependencies, Makefile/Justfile,. |
| [`observability`](../plugins/ai-toolkit-java-ops/skills/observability/SKILL.md) | Java / Spring Boot observability — Micrometer + Prometheus metrics, JSON logs with MDC correlation IDs, OpenTelemetry traces, SLI/SLO conventions. |
| [`request-metrics`](../plugins/ai-toolkit-java-ops/skills/request-metrics/SKILL.md) | Java / Spring Boot per-endpoint Micrometer timers via Filter + Recorder + Parser — one OncePerRequestFilter, one MetricsRecorder per use case, pluggable tag par. |
| [`component-tests`](../plugins/ai-toolkit-java-quality/skills/component-tests/SKILL.md) | Java / Spring Boot component tests — boot the full context with a test profile, replace external collaborators with deterministic doubles, exercise the HTTP API. |
| [`golden-path`](../plugins/ai-toolkit-java-quality/skills/golden-path/SKILL.md) | The Java / Spring Boot golden path — the apply-order of the skills and the 24 non-negotiables every diff must satisfy. |
| [`quality-review`](../plugins/ai-toolkit-java-quality/skills/quality-review/SKILL.md) | Java / Spring Boot code review of a class, package or PR — SOLID, clean code, LEGO-brick packaging, testability anti-patterns, exception/logging/concurrency con. |
| [`static-analysis`](../plugins/ai-toolkit-java-quality/skills/static-analysis/SKILL.md) | Java / Spring Boot static analysis wired into Maven so violations break the build — Spotless, SpotBugs, Error-Prone, NullAway, Checkstyle, Sonar profile. |
| [`unit-tests`](../plugins/ai-toolkit-java-quality/skills/unit-tests/SKILL.md) | Java / Spring Boot JUnit 5 + Mockito unit tests — positive, negative and edge cases, every error branch, methodName_Condition_ExpectedResult naming, Jacoco thre. |
| [`create-repo`](../plugins/ai-toolkit-java-scaffold/skills/create-repo/SKILL.md) | Java / Spring Boot repository scaffolder — asks for project metadata, then applies ci, cd and code-structure to produce Jenkinsfile, Dockerfile, pom. |
| [`project-types`](../plugins/ai-toolkit-java-scaffold/skills/project-types/SKILL.md) | Java / Spring Boot meta-skill — picks the skill set for the kind of service: synchronous REST, event-driven, scheduler/batch, library/SDK, or monolith with micr. |
| [`python-error-handling`](../plugins/ai-toolkit-python-build/skills/python-error-handling/SKILL.md) | Python / FastAPI error contract — typed exception hierarchy, error-code and message catalogue, ONE handler mapping errors to RFC 7807 problem+json. |
| [`python-input-validation`](../plugins/ai-toolkit-python-build/skills/python-input-validation/SKILL.md) | Python input validation with pydantic v2 — Field constraints and validated types, model validators for cross-field rules, injectable rule objects, custom messag. |
| [`python-code-structure`](../plugins/ai-toolkit-python-design/skills/python-code-structure/SKILL.md) | Python 3. |
| [`python-fastapi-conventions`](../plugins/ai-toolkit-python-design/skills/python-fastapi-conventions/SKILL.md) | Python FastAPI conventions — thin routers, Depends injection, explicit response models, one pagination contract, problem+json errors, lifespan-managed resources. |
| [`python-ci`](../plugins/ai-toolkit-python-ops/skills/python-ci/SKILL.md) | Python 3. |
| [`python-static-analysis`](../plugins/ai-toolkit-python-quality/skills/python-static-analysis/SKILL.md) | Python static analysis — ruff lint and format, mypy --strict, pre-commit, one pyproject. |
| [`python-unit-tests`](../plugins/ai-toolkit-python-quality/skills/python-unit-tests/SKILL.md) | Python pytest unit tests — positive, negative and edge cases, method_condition_expectedResult naming, fixtures, fakes at the boundary, parametrize, coverage thr. |
| [`code-hygiene`](../plugins/ai-toolkit-quality/skills/code-hygiene/SKILL.md) | Keep a diff minimal and self-explanatory — no comments restating code, no dead code, no speculative abstraction, no unrelated churn, no redundant tests. |
| [`completion-gate`](../plugins/ai-toolkit-quality/skills/completion-gate/SKILL.md) | Definition of done — never commit until asked; before saying done, prove build, full tests, static analysis, language standards, meaningful coverage, hygiene an. |
| [`react-native-error-handling`](../plugins/ai-toolkit-react-native-build/skills/react-native-error-handling/SKILL.md) | React Native error contract — typed AppError hierarchy, message catalogue, API-error mapping in one place, error boundaries, reporting hook. |
| [`react-native-input-validation`](../plugins/ai-toolkit-react-native-build/skills/react-native-input-validation/SKILL.md) | React Native input validation with zod schemas in a validation layer, react-hook-form, cross-field rules, schemas shared with API types. |
| [`react-native-security`](../plugins/ai-toolkit-react-native-build/skills/react-native-security/SKILL.md) | React Native security baseline — tokens in Keychain/Keystore, no secrets in the JS bundle, deep-link validation, TLS and pinning stance, PII-free logging. |
| [`react-native-code-structure`](../plugins/ai-toolkit-react-native-design/skills/react-native-code-structure/SKILL.md) | React Native feature-based layout — TypeScript strict, path aliases, dependency direction, naming for screens, components, hooks, services and api. |
| [`react-native-state-and-data`](../plugins/ai-toolkit-react-native-design/skills/react-native-state-and-data/SKILL.md) | React Native data layer — server state in TanStack Query behind one api client, client state in Zustand, query-key conventions, optimistic updates, offline/retr. |
| [`react-native-ci`](../plugins/ai-toolkit-react-native-ops/skills/react-native-ci/SKILL.md) | React Native CI/CD on GitHub Actions — cached installs, lint/type/test gates, EAS Build or Fastlane, versioning and build numbers, OTA update stance. |
| [`react-native-static-analysis`](../plugins/ai-toolkit-react-native-quality/skills/react-native-static-analysis/SKILL.md) | React Native static analysis — TypeScript strict, ESLint flat config, Prettier, boundary rules, lint-staged and husky, all breaking the CI build. |
| [`react-native-unit-tests`](../plugins/ai-toolkit-react-native-quality/skills/react-native-unit-tests/SKILL.md) | React Native unit tests with Jest + React Native Testing Library — behaviour-focused queries, MSW for network, fakes over mocks, positive/negative/edge cases, c. |
| [`git-commit-conventions`](../plugins/ai-toolkit-workflow/skills/git-commit-conventions/SKILL.md) | Git commits that stay reviewable and bisectable — Conventional Commit prefixes, small single-purpose commits that each build, subject/body format, commit-msg ho. |
| [`release-versioning`](../plugins/ai-toolkit-workflow/skills/release-versioning/SKILL.md) | Release lifecycle — Conventional Commits, Semantic Versioning, automated CHANGELOG (release-please or semantic-release), git tag = artifact version, deprecation. |

### SHOULD — when the service has the feature (22)

| Skill | One-line summary |
| --- | --- |
| [`uml-diagram`](../plugins/ai-toolkit-docs/skills/uml-diagram/SKILL.md) | Create and maintain UML diagrams using Mermaid to visualize system architecture, component relationships, and interaction flows. |
| [`messaging`](../plugins/ai-toolkit-java-build/skills/messaging/SKILL.md) | Java / Spring Boot Kafka or RabbitMQ — idempotent consumer, transactional outbox, dead-letter topic and redelivery, schema management (Avro/Protobuf/JSON-Schema. |
| [`persistence`](../plugins/ai-toolkit-java-build/skills/persistence/SKILL.md) | Java / Spring Boot persistence — Spring Data JPA repositories and entities, Flyway migrations, transaction boundaries, optimistic locking, auditing, soft delete. |
| [`rate-limiting`](../plugins/ai-toolkit-java-build/skills/rate-limiting/SKILL.md) | Java / Spring Boot: Protect the service from abuse and ensure fair usage using rate-limiting strategies. |
| [`sdk-publishing`](../plugins/ai-toolkit-java-build/skills/sdk-publishing/SKILL.md) | Java / Spring Boot library or starter — auto-configuration with @ConditionalOnMissingBean defaults, configuration metadata, minimal API surface, semantic versio. |
| [`async-api-patterns`](../plugins/ai-toolkit-java-design/skills/async-api-patterns/SKILL.md) | Java / Spring Boot long-running operations — submit-poll-result jobs, webhooks, SSE, job state, cleanup of abandoned jobs, idempotent submits. |
| [`domain-modeling`](../plugins/ai-toolkit-java-design/skills/domain-modeling/SKILL.md) | Java / Spring Boot tactical DDD — bounded context, aggregate root, entity, value object, domain event, domain service, repository, anti-corruption layer, specif. |
| [`feature-flags`](../plugins/ai-toolkit-java-design/skills/feature-flags/SKILL.md) | Java / Spring Boot feature toggles — local config toggles, remote providers (Unleash, LaunchDarkly), toggle-at-the-edge vs toggle-in-logic, flag lifecycle and c. |
| [`openapi-first-codegen`](../plugins/ai-toolkit-java-design/skills/openapi-first-codegen/SKILL.md) | Java / Spring Boot OpenAPI-first — generate controllers and DTOs from api. |
| [`response-layout`](../plugins/ai-toolkit-java-design/skills/response-layout/SKILL.md) | Java / Spring Boot ?layout= parameter (summary/detailed/full) via Strategy + Handler + Registry — one LayoutStrategy per field set. |
| [`response-mapper`](../plugins/ai-toolkit-java-design/skills/response-mapper/SKILL.md) | Java / Spring Boot API versioning and response projections via Strategy + Handler + Registry — version resolved from Accept header, URI or query param; one Mapp. |
| [`health-indicator`](../plugins/ai-toolkit-java-ops/skills/health-indicator/SKILL.md) | Java / Spring Boot Actuator readiness HealthIndicator for a downstream dependency, wired into the readiness group and Helm chart; asks for name, URL, endpoint, . |
| [`adapter-contract-tests`](../plugins/ai-toolkit-java-quality/skills/adapter-contract-tests/SKILL.md) | Java / Spring Boot adapter contract tests — one abstract, vendor-neutral suite (TCK) per port, subclassed by every adapter (often with Testcontainers) so swappi. |
| [`integration-tests`](../plugins/ai-toolkit-java-quality/skills/integration-tests/SKILL.md) | Java / Spring Boot integration tests against real dependencies (DB, broker, object store, mocked HTTP) with Testcontainers, Surefire/Failsafe split, optional Pa. |
| [`python-persistence`](../plugins/ai-toolkit-python-build/skills/python-persistence/SKILL.md) | Python persistence with SQLAlchemy 2. |
| [`python-observability`](../plugins/ai-toolkit-python-ops/skills/python-observability/SKILL.md) | Python / FastAPI observability — structlog JSON logs with contextvars correlation IDs, OpenTelemetry traces, prometheus-client metrics with low-cardinality labe. |
| [`python-integration-tests`](../plugins/ai-toolkit-python-quality/skills/python-integration-tests/SKILL.md) | Python integration tests with testcontainers-python (PostgreSQL, Redis, Kafka) and pytest markers separating unit from integration, including Alembic migration . |
| [`sonar-quality-gate`](../plugins/ai-toolkit-quality/skills/sonar-quality-gate/SKILL.md) | Drive the SonarQube/SonarCloud new-code quality gate to green — bugs, vulnerabilities, smells, hotspots, duplication, coverage — without suppressing findings; r. |
| [`react-native-observability`](../plugins/ai-toolkit-react-native-ops/skills/react-native-observability/SKILL.md) | React Native observability — Sentry crash and performance monitoring, structured logging, analytics behind an interface, PII scrubbing, release health. |
| [`react-native-e2e-tests`](../plugins/ai-toolkit-react-native-quality/skills/react-native-e2e-tests/SKILL.md) | React Native end-to-end tests with Maestro — stable test IDs, deterministic test data, a clear E2E vs unit split. |
| [`parallel-delegation`](../plugins/ai-toolkit-workflow/skills/parallel-delegation/SKILL.md) | When and how to hand work to subagents in parallel without conflicts — what is safe to delegate, how to brief a subagent, file ownership, verifying results. |
| [`pr-description`](../plugins/ai-toolkit-workflow/skills/pr-description/SKILL.md) | Pull request descriptions on Bitbucket Server — problem, solution, key changes, testing, notes; fetch and update the PR atomically via the REST API with optimis. |

### FOUNDATIONAL — patterns other skills build on (2)

| Skill | One-line summary |
| --- | --- |
| [`validation-pattern`](../plugins/ai-toolkit-java-build/skills/validation-pattern/SKILL.md) | Java / Spring Boot: background and rationale for input validation — why rules live in annotations, validators and rule beans, message design and testing strateg. |
| [`strategy-registry-pattern`](../plugins/ai-toolkit-java-design/skills/strategy-registry-pattern/SKILL.md) | Java / Spring Boot Strategy + Registry + Handler for runtime-selected behaviour — add a strategy class, never edit the dispatcher (Open/Closed). |

### MAY — useful but optional (1)

| Skill | One-line summary |
| --- | --- |
| [`refactoring-playbook`](../plugins/ai-toolkit-java-quality/skills/refactoring-playbook/SKILL.md) | Java / Spring Boot step-by-step migrations — @Value to @ConfigurationProperties, type switches to Strategy + Handler, RestTemplate to RestClient/WebClient, hand. |

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
create-repo (HITL)                       ← generates skeleton, asks 18 questions
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
    when an `*Adapter` has no matching `*ContractTest` or `*ContractIT`
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
    DTOs never escape the package, and every non-2xx is mapped to a domain
    exception inside it. In the Full 5-Layer pattern, `exchangeToMono` +
    `handleResponse` handles all non-2xx, and filter map, request building,
    response parsing, and boolean response checks each live in their own
    dedicated class (`external-client`).
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


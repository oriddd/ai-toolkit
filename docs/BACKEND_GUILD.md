# Backend Guild — Golden Path

This is the **curated bundle** that every backend service your team
builds should follow when an agent (or a human) generates code. It
filters the atomic skills in [`REGISTRY.md`](./REGISTRY.md) into a
**MUST / SHOULD / MAY** adoption matrix, an apply-order sequence, and
task-driven recipes.

> Code that does not satisfy the **MUST** column should not pass your
> team's PR review.

> **Scope.** The recipes and the 24 non-negotiables below are the **Java 21 / Spring Boot 3.5.x**
> golden path (the Java skills are written and verified against Boot 3.5). The adoption matrix lists every skill in the marketplace — Java, the
> language-neutral workflow/docs/quality skills, and the Python / React Native drafts. For a
> non-Java project follow that language's `hooks/routing.md` and the Do/Don't lists of its
> `python-*` / `react-native-*` skills; the *principles* (LEGO bricks, one canonical pattern,
> validation layer, typed errors, no commit until asked, `completion-gate`) are identical.

## 1. Adoption matrix

> **Reading the MUST list.** It is generated from every skill's `tier`, so it spans all
> languages. Apply only the rows for your language, plus the language-neutral ones. Some MUST
> rows are conditional: pick **one** of `ci` / `github-actions-ci`; apply `data-privacy` when the
> service handles personal data; `create-repo` and `project-types` apply once, when the repo is
> created.

<!-- BEGIN AUTO:matrix -->
### MUST — Java baseline (alternatives and conditional skills are noted under the table) (33)

| Skill | One-line summary |
| --- | --- |
| [`context-maintenance`](../plugins/ai-toolkit-docs/skills/context-maintenance/SKILL.md) | Maintain project context documentation including architecture, standards, build plans, and progress tracking. |
| [`documentation-and-adr`](../plugins/ai-toolkit-docs/skills/documentation-and-adr/SKILL.md) | Docs as code — README, CONTRIBUTING, ARCHITECTURE (C4 in PlantUML/Structurizr), ADRs under docs/adr/, generated class and sequence diagrams. |
| [`data-privacy`](../plugins/ai-toolkit-java-build/skills/data-privacy/SKILL.md) | Handle PII (Personally Identifiable Information) and GDPR requirements in a Java microservice — field-level encryption, masking in logs, data retention/TTL … |
| [`exception-handling`](../plugins/ai-toolkit-java-build/skills/exception-handling/SKILL.md) | Java / Spring Boot error contract — typed domain exception hierarchy, static ExceptionMessages catalogue, @RestControllerAdvice mapping each exception to an … |
| [`external-client`](../plugins/ai-toolkit-java-build/skills/external-client/SKILL.md) | Java / Spring Boot: SDK-style package for a downstream service (HTTP, gRPC, broker, file store) — Service facade, CoreService, thin Client, request builders … |
| [`input-validation`](../plugins/ai-toolkit-java-build/skills/input-validation/SKILL.md) | Java / Spring Boot input validation — Jakarta ConstraintValidator for field/parameter rules, Spring Validator for cross-field rules, custom annotations … |
| [`permissions`](../plugins/ai-toolkit-java-build/skills/permissions/SKILL.md) | Java / Spring Boot authorization via Strategy + Handler — PermissionsHandler dispatches by caller context (user, service account, external system) to … |
| [`resilience-patterns`](../plugins/ai-toolkit-java-build/skills/resilience-patterns/SKILL.md) | Java / Spring Boot stability with Resilience4j — timeouts, bulkheads, circuit breakers, fallbacks, fail-fast. |
| [`security-hardening`](../plugins/ai-toolkit-java-build/skills/security-hardening/SKILL.md) | Java / Spring Boot security beyond authn/authz — OWASP Top 10 checklist, CORS, security headers, secret management, dependency scanning, image signing. |
| [`api-design`](../plugins/ai-toolkit-java-design/skills/api-design/SKILL.md) | Java / Spring Boot REST API design — resources and URLs, HTTP verbs, status codes, versioning, pagination/filtering/sorting, deprecation headers, RFC 9457 … |
| [`code-structure`](../plugins/ai-toolkit-java-design/skills/code-structure/SKILL.md) | Java / Spring Boot package hierarchy and layering — controller/operation/service, filter + recorder; every class a small, testable LEGO brick. |
| [`pattern-selection`](../plugins/ai-toolkit-java-design/skills/pattern-selection/SKILL.md) | Java / Spring Boot: choose the smallest pattern that fits the actual scale — decision tables for clients, operations and layers, over-engineering red flags. |
| [`pluggable-architecture`](../plugins/ai-toolkit-java-design/skills/pluggable-architecture/SKILL.md) | Java / Spring Boot ports and adapters — every external technology (cache, DB, broker, metrics, object store, secrets, identity) behind a port, with adapters … |
| [`spring-boot-conventions`](../plugins/ai-toolkit-java-design/skills/spring-boot-conventions/SKILL.md) | Java / Spring Boot 3 idioms — @ConfigurationProperties over @Value, profiles, conditional beans, @Async with named executors, caching, pagination, idempotency … |
| [`testable-code-principles`](../plugins/ai-toolkit-java-design/skills/testable-code-principles/SKILL.md) | Java / Spring Boot testability principles — small LEGO-brick classes, names over comments, SOLID mapped to testing, no static methods, global state or hidden … |
| [`cd`](../plugins/ai-toolkit-java-ops/skills/cd/SKILL.md) | Java / Spring Boot Helm chart for Kubernetes — hardened security context, Actuator liveness/readiness probes, HPA, Prometheus ServiceMonitor, credentials … |
| [`ci`](../plugins/ai-toolkit-java-ops/skills/ci/SKILL.md) | Java 21 / Spring Boot CI with Jenkins — declarative Jenkinsfile, multi-stage Dockerfile, Maven build. |
| [`github-actions-ci`](../plugins/ai-toolkit-java-ops/skills/github-actions-ci/SKILL.md) | Java / Spring Boot CI on GitHub Actions — build, test, image, release, commit-lint and dependency-scan workflows on GitHub-hosted runners. |
| [`graceful-shutdown`](../plugins/ai-toolkit-java-ops/skills/graceful-shutdown/SKILL.md) | Java / Spring Boot graceful shutdown — drain in-flight requests, async work, consumers and clients on Kubernetes pod termination. |
| [`local-dev-experience`](../plugins/ai-toolkit-java-ops/skills/local-dev-experience/SKILL.md) | Java / Spring Boot inner loop in under 5 minutes — docker-compose for dependencies, Makefile/Justfile, .devcontainer, .editorconfig, pre-commit hooks (format … |
| [`observability`](../plugins/ai-toolkit-java-ops/skills/observability/SKILL.md) | Java / Spring Boot observability — Micrometer + Prometheus metrics, JSON logs with MDC correlation IDs, OpenTelemetry traces, SLI/SLO conventions. |
| [`request-metrics`](../plugins/ai-toolkit-java-ops/skills/request-metrics/SKILL.md) | Java / Spring Boot per-endpoint Micrometer timers via Filter + Recorder + Parser — one OncePerRequestFilter, one MetricsRecorder per use case, pluggable tag … |
| [`component-tests`](../plugins/ai-toolkit-java-quality/skills/component-tests/SKILL.md) | Java / Spring Boot component tests — boot the full context with a test profile, replace external collaborators with deterministic doubles, exercise the HTTP … |
| [`golden-path`](../plugins/ai-toolkit-java-quality/skills/golden-path/SKILL.md) | The Java / Spring Boot golden path — the apply-order of the skills and the 24 non-negotiables every diff must satisfy. |
| [`quality-review`](../plugins/ai-toolkit-java-quality/skills/quality-review/SKILL.md) | Java / Spring Boot code review of a class, package or PR — SOLID, clean code, LEGO-brick packaging, testability anti-patterns, exception/logging/concurrency … |
| [`static-analysis`](../plugins/ai-toolkit-java-quality/skills/static-analysis/SKILL.md) | Java / Spring Boot static analysis wired into Maven so violations break the build — Spotless, SpotBugs, Error-Prone, NullAway, Checkstyle, Sonar profile. |
| [`unit-tests`](../plugins/ai-toolkit-java-quality/skills/unit-tests/SKILL.md) | Java / Spring Boot JUnit 5 + Mockito unit tests — positive, negative and edge cases, every error branch, methodName_condition_expectedResult naming, Jacoco and … |
| [`create-repo`](../plugins/ai-toolkit-java-scaffold/skills/create-repo/SKILL.md) | Java / Spring Boot repository scaffolder — asks for project metadata, then applies ci, cd and code-structure to produce Jenkinsfile, Dockerfile, pom.xml, Helm … |
| [`project-types`](../plugins/ai-toolkit-java-scaffold/skills/project-types/SKILL.md) | Java / Spring Boot meta-skill — picks the skill set for the kind of service: synchronous REST, event-driven, scheduler/batch, library/SDK, or monolith with … |
| [`code-hygiene`](../plugins/ai-toolkit-quality/skills/code-hygiene/SKILL.md) | Keep a diff minimal and self-explanatory — no comments restating code, no dead code, no speculative abstraction, no unrelated churn, no redundant tests. |
| [`completion-gate`](../plugins/ai-toolkit-quality/skills/completion-gate/SKILL.md) | Definition of done — never commit until asked; before saying done, prove build, full tests, static analysis, language standards, meaningful coverage, hygiene … |
| [`git-commit-conventions`](../plugins/ai-toolkit-workflow/skills/git-commit-conventions/SKILL.md) | Git commits that stay reviewable and bisectable — Conventional Commit prefixes, small single-purpose commits that each build, subject/body format, commit-msg … |
| [`release-versioning`](../plugins/ai-toolkit-workflow/skills/release-versioning/SKILL.md) | Release lifecycle — Conventional Commits, Semantic Versioning, automated CHANGELOG (release-please or semantic-release), git tag = artifact version … |

> **Alternatives:** `ci` (Jenkins) and `github-actions-ci` — pick one per repo.
>
> **Once per repo:** `create-repo`, `project-types` apply when the repo is created.
>
> **Conditional:** `data-privacy` applies when the service processes personal data.
>
> **Other languages:** Python and React Native skills are not listed here — see their routing tables and [`LANGUAGE_CONTRACT.md`](./LANGUAGE_CONTRACT.md).

### SHOULD — when the service has the feature (17)

| Skill | One-line summary |
| --- | --- |
| [`uml-diagram`](../plugins/ai-toolkit-docs/skills/uml-diagram/SKILL.md) | Create and maintain UML diagrams using Mermaid to visualize system architecture, component relationships, and interaction flows. |
| [`messaging`](../plugins/ai-toolkit-java-build/skills/messaging/SKILL.md) | Java / Spring Boot Kafka or RabbitMQ — idempotent consumer, transactional outbox, dead-letter topic and redelivery, schema management … |
| [`persistence`](../plugins/ai-toolkit-java-build/skills/persistence/SKILL.md) | Java / Spring Boot persistence — Spring Data JPA repositories and entities, Flyway migrations, transaction boundaries, optimistic locking, auditing, soft … |
| [`rate-limiting`](../plugins/ai-toolkit-java-build/skills/rate-limiting/SKILL.md) | Java / Spring Boot: Protect the service from abuse and ensure fair usage using rate-limiting strategies. |
| [`sdk-publishing`](../plugins/ai-toolkit-java-build/skills/sdk-publishing/SKILL.md) | Java / Spring Boot library or starter — auto-configuration with @ConditionalOnMissingBean defaults, configuration metadata, minimal API surface, semantic … |
| [`async-api-patterns`](../plugins/ai-toolkit-java-design/skills/async-api-patterns/SKILL.md) | Java / Spring Boot long-running operations — submit-poll-result jobs, webhooks, SSE, job state, cleanup of abandoned jobs, idempotent submits. |
| [`domain-modeling`](../plugins/ai-toolkit-java-design/skills/domain-modeling/SKILL.md) | Java / Spring Boot tactical DDD — bounded context, aggregate root, entity, value object, domain event, domain service, repository, anti-corruption layer … |
| [`feature-flags`](../plugins/ai-toolkit-java-design/skills/feature-flags/SKILL.md) | Java / Spring Boot feature toggles — local config toggles, remote providers (Unleash, LaunchDarkly), toggle-at-the-edge vs toggle-in-logic, flag lifecycle and … |
| [`openapi-first-codegen`](../plugins/ai-toolkit-java-design/skills/openapi-first-codegen/SKILL.md) | Java / Spring Boot OpenAPI-first — generate controllers and DTOs from api.yaml with openapi-generator-maven-plugin, exclude generated code from coverage and … |
| [`response-layout`](../plugins/ai-toolkit-java-design/skills/response-layout/SKILL.md) | Java / Spring Boot ?layout= parameter (summary/detailed/full) via Strategy + Handler + Registry — one LayoutStrategy per field set. |
| [`response-mapper`](../plugins/ai-toolkit-java-design/skills/response-mapper/SKILL.md) | Java / Spring Boot API versioning and response projections via Strategy + Handler + Registry — version resolved from Accept header, URI or query param; one … |
| [`health-indicator`](../plugins/ai-toolkit-java-ops/skills/health-indicator/SKILL.md) | Java / Spring Boot Actuator readiness HealthIndicator for a downstream dependency, wired into the readiness group and Helm chart; asks for name, URL, endpoint … |
| [`adapter-contract-tests`](../plugins/ai-toolkit-java-quality/skills/adapter-contract-tests/SKILL.md) | Java / Spring Boot adapter contract tests — one abstract, vendor-neutral suite (TCK) per port, subclassed by every adapter (often with Testcontainers) so … |
| [`integration-tests`](../plugins/ai-toolkit-java-quality/skills/integration-tests/SKILL.md) | Java / Spring Boot integration tests against real dependencies (DB, broker, object store, mocked HTTP) with Testcontainers, Surefire/Failsafe split, optional … |
| [`sonar-quality-gate`](../plugins/ai-toolkit-quality/skills/sonar-quality-gate/SKILL.md) | Drive the SonarQube/SonarCloud new-code quality gate to green — bugs, vulnerabilities, smells, hotspots, duplication, coverage — without suppressing findings … |
| [`parallel-delegation`](../plugins/ai-toolkit-workflow/skills/parallel-delegation/SKILL.md) | When and how to hand work to subagents in parallel without conflicts — what is safe to delegate, how to brief a subagent, file ownership, verifying results. |
| [`pr-description`](../plugins/ai-toolkit-workflow/skills/pr-description/SKILL.md) | Pull request descriptions — problem, solution, key changes, testing, notes; update the PR on any git host (GitHub, GitLab, Azure DevOps, Bitbucket) without … |

### FOUNDATIONAL — patterns other skills build on (2)

| Skill | One-line summary |
| --- | --- |
| [`validation-pattern`](../plugins/ai-toolkit-java-build/skills/validation-pattern/SKILL.md) | Java / Spring Boot: background and rationale for input validation — why rules live in annotations, validators and rule beans, message design and testing … |
| [`strategy-registry-pattern`](../plugins/ai-toolkit-java-design/skills/strategy-registry-pattern/SKILL.md) | Java / Spring Boot Strategy + Registry + Handler for runtime-selected behaviour — add a strategy class, never edit the dispatcher (Open/Closed). |

### MAY — useful but optional (1)

| Skill | One-line summary |
| --- | --- |
| [`refactoring-playbook`](../plugins/ai-toolkit-java-quality/skills/refactoring-playbook/SKILL.md) | Java / Spring Boot step-by-step migrations — @Value to @ConfigurationProperties, type switches to Strategy + Handler, RestTemplate to RestClient/WebClient … |

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
  python_code_structure --> python_external_client
  python_error_handling --> python_external_client
  python_code_structure --> python_input_validation
  python_error_handling --> python_input_validation
  python_code_structure --> python_messaging
  python_persistence --> python_messaging
  python_error_handling --> python_messaging
  python_code_structure --> python_persistence
  python_error_handling --> python_persistence
  python_code_structure --> python_security
  python_fastapi_conventions --> python_security
  python_error_handling --> python_security
  python_code_structure --> python_fastapi_conventions
  python_static_analysis --> python_ci
  python_unit_tests --> python_ci
  python_code_structure --> python_observability
  python_unit_tests --> python_integration_tests
  python_persistence --> python_integration_tests
  python_code_structure --> python_static_analysis
  python_code_structure --> python_unit_tests
  code_hygiene --> completion_gate
  sonar_quality_gate --> completion_gate
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
create-repo (HITL, main session)         ← generates skeleton, asks its Phase 1 questions
        │
        ├─► code-structure               ← packages, base classes
        ├─► spring-boot-conventions      ← config, profiles, async, scheduled
        ├─► api-design  ─►  openapi-first-codegen (optional)
        ├─► exception-handling
        ├─► permissions                  ← SPIs only; concrete resolver is yours to supply
        ├─► external-client              ← one sub-package per downstream
        ├─► persistence (Flyway migrations)
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

`pluggable-architecture` (define the `spi/` port → `adapter/<capability>/<vendor>/`
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

These are the rules your maintainers enforce during PR review. Every agent
producing code must validate the diff against this list before returning.

1. **Package layout** matches `code-structure` §1 exactly — including the
   feature packages listed there (`config/`, `spi/`, `adapter/`, `validation/`,
   `entity/`, `messaging/`, …), created only when the service uses them.
2. **Config** is `@ConfigurationProperties` (record), never `@Value` for
   grouped properties (`spring-boot-conventions` §1).
3. **Controllers contain no business logic**; each endpoint calls one
   `*Operation` when the use case orchestrates several services, otherwise
   one `*Service` (`code-structure`).
4. **Exceptions** extend the project's **unchecked** domain hierarchy (rooted
   in a base exception that extends `RuntimeException`, so no `throws`
   clauses and `@Transactional` rolls back by default) and are built from
   the `ExceptionMessages` catalogue, which supplies the error code and
   message (`exception-handling`).
5. **Authorization** goes through `PermissionsHandler`, never inline
   `if (principal.isAdmin)` (`permissions`).
6. **Outbound HTTP** goes through the `client/<dep>/` sub-package (see #23) —
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
   (`spring-boot-conventions` §8); the provider sits behind a cache port as
   in #20 (`pluggable-architecture`).
10. **Messaging consumers** are idempotent and have a DLQ wired
    (`messaging`).
11. **Logs** are JSON with MDC correlation IDs; no `e.printStackTrace()`
    (`observability`).
12. **Tests**: PIT mutation score ≥ 75 %; Jacoco ≥ 85 % line / ≥ 75 % branch
    per class, enforced by the jacoco `check` goal in the build (`ci`
    `pom.xml.tmpl`); no `@MockitoBean` (legacy `@MockBean`) on the class
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
17. **Graceful shutdown** is enabled (`server.shutdown=graceful` +
    `spring.lifecycle.timeout-per-shutdown-phase`) and exercised by a test —
    a component test asserting the shutdown settings, plus the skill's
    rolling-update smoke test (`graceful-shutdown`).
18. **Releases** use Conventional Commits; CHANGELOG is automated
    (`release-versioning`).
19. **`context/` documentation** is updated in the same PR as the code
    change it describes (`context-maintenance`).
20. **External technology is behind a port.** Any integration with an
    external tool (cache, DB dialect, metrics backend, broker, object
    store, secret manager, identity provider, …) is consumed through a
    project-owned `spi/` port; the vendor SDK is imported **only** inside
    `adapter/<capability>/<vendor>/`; selection/composition is config-driven in
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
    Callers depend only on the package's public entry type — `<Dep>Service`
    in Full 5-Layer, `<Dep>Client` in Simple Wrapper and Lite; `WebClient`,
    `RestClient`, `Mono`, `Flux`, and remote
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

This file is a contract between your maintainers and code-generating agents.
Loosening any of the **24 non-negotiables** requires:

1. An ADR proposing the change under `docs/adr/`.
2. Approval from the maintainers responsible for the catalogue.
3. A matching update to [`REGISTRY.md`](./REGISTRY.md) and the affected
   `SKILL.md`.
4. `bash tools/validate-skills.sh` passing on the same PR.
5. Explicit sign-off from the maintainers when the change weakens an
   enforcement (e.g. lowering the mutation-score threshold).


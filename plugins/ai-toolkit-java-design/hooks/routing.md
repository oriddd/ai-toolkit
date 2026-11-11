## ai-toolkit Java / Spring Boot standards (MANDATORY routing)

Skills apply only if LOADED — no code from memory. Load with the Skill tool as `<plugin>:<skill>`
(never bare), before asking clarifying questions. Plugin letters: (d) `ai-toolkit-java-design`, (b) `ai-toolkit-java-build`,
(q) `ai-toolkit-java-quality`, (o) `ai-toolkit-java-ops`; others are written in full.

| Task | Load first |
| --- | --- |
| New service / repository from scratch | `project-types` (ai-toolkit-java-scaffold), `create-repo` (ai-toolkit-java-scaffold) |
| Any Java class / package / controller / service | `code-structure` (d), `testable-code-principles` (d) |
| New layer, client package, pattern or abstraction | `pattern-selection` (d) |
| Strategy + registry, `?layout=`, response versions | `strategy-registry-pattern` (d), `response-layout` (d), `response-mapper` (d) |
| Domain model, aggregate, value object | `domain-modeling` (d) |
| Config, `@Value`, `@Async`, caching | `spring-boot-conventions` (d) |
| New REST endpoint | `api-design` (d), `permissions` (b), `exception-handling` (b), `input-validation` (b) |
| Who may call (roles, admins, owner) | `permissions` (b) |
| OpenAPI spec / generated controllers | `openapi-first-codegen` (d) |
| Long-running API, feature toggle | `async-api-patterns` (d), `feature-flags` (d) |
| Errors; validation rule | `exception-handling` (b); `input-validation` (b), `validation-pattern` (b) |
| Entity / repository; Kafka / RabbitMQ | `persistence` (b); `messaging` (b) |
| Call an external service | `external-client` (b), `resilience-patterns` (b) |
| Rate limit, security, personal data | `rate-limiting` (b), `security-hardening` (b), `data-privacy` (b) |
| Shared library / starter | `sdk-publishing` (b) |
| Endpoint metric, logs, traces | `request-metrics` (o), `observability` (o) |
| Readiness, graceful shutdown, local dev | `health-indicator` (o), `graceful-shutdown` (o), `local-dev-experience` (o) |
| Pipeline, deployment | `ci` (o) or `github-actions-ci` (o) — never both; `cd` (o) |
| Swap a cache / broker / DB / secret store | `pluggable-architecture` (d), `adapter-contract-tests` (q) |
| Tests, lint, static analysis | `unit-tests` (q), `component-tests` (q), `integration-tests` (q), `static-analysis` (q) |
| Refactor legacy code to the standard | `refactoring-playbook` (q) |
| Plan a change, review a diff | `golden-path` (q), `quality-review` (q) |
| README, ADR, diagrams, context docs | `ai-toolkit-docs:documentation-and-adr`, `ai-toolkit-docs:uml-diagram`, `ai-toolkit-docs:context-maintenance` |

Agents: `ai-toolkit-java-agents:` new-endpoint, new-feature, new-validation, new-metric, new-microservice-client,
new-kafka-consumer, refactor, scaffold-repo, test-writer, code-review; `ai-toolkit-docs:update-context`.

Gates: smallest pattern that fits. Before done, run `ai-toolkit-quality:completion-gate` (the project's build,
wrapper first: `mvn -B clean verify` or `./gradlew build`) and review the diff against `golden-path`. Never commit unless
the developer asks. Postman skills: Postman collections/workspaces only. `CLAUDE.md` overrides skill defaults.

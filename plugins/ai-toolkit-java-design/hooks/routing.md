## ai-toolkit Java / Spring Boot standards (MANDATORY routing)

Standards apply only if the skill is LOADED first — do not write code from memory. Load with the Skill tool using the
qualified name `ai-toolkit-java-<phase>:<skill>`, phase d=design, b=build, q=quality, o=ops; scaffold skills show their
full plugin name (bare names can resolve to stale copies).

| Task | Load first |
| --- | --- |
| New service / repository from scratch | `project-types` (ai-toolkit-java-scaffold), `create-repo` (ai-toolkit-java-scaffold) |
| Any Java class / package / controller / service | `code-structure` (d), `testable-code-principles` (d), `pattern-selection` (d) |
| Config, `@Value`, `@Async`, caching | `spring-boot-conventions` (d) |
| New REST endpoint | `api-design` (d), `permissions` (b), `exception-handling` (b), `input-validation` (b) |
| Long-running API, feature toggle | `async-api-patterns` (d), `feature-flags` (d) |
| Throwing / mapping errors | `exception-handling` (b) |
| Validation rule | `input-validation` (b) |
| Entity / repository | `persistence` (b) |
| Kafka / RabbitMQ | `messaging` (b) |
| Call an external service | `external-client` (b), `resilience-patterns` (b) |
| Rate limit, security, personal data | `rate-limiting` (b), `security-hardening` (b), `data-privacy` (b) |
| Endpoint metric, logs, traces | `request-metrics` (o), `observability` (o) |
| Pipeline, deployment | `ci` (o) or `github-actions-ci` (o), `cd` (o) |
| Swap a cache / broker / DB / secret store | `pluggable-architecture` (d) |
| Tests, lint, static analysis | `unit-tests` (q), `component-tests` (q), `integration-tests` (q), `static-analysis` (q) |
| Plan a change, review a diff | `golden-path` (q), `quality-review` (q) |

Gates: smallest pattern that fits. Before saying done run `ai-toolkit-quality:completion-gate` (Java: `mvn -B clean
verify`) and review the diff against `golden-path`. Never commit unless the developer asks. Postman skills apply only to Postman collections or workspaces — code
standards come from this table.

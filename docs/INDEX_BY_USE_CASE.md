# Index by Use Case

This index helps you find the right skills to read based on the task you are performing.

| If you want to... | Read these skills (in order) |
| :--- | :--- |
| **Start a new microservice** | `project-types`, `create-repo`, `ci`, `github-actions-ci` (instead of `ci` on GitHub), `cd`, `code-structure`, `spring-boot-conventions`, `api-design`, `exception-handling`, `health-indicator`, `observability`, `unit-tests`, `component-tests`, `static-analysis`, `documentation-and-adr`, `context-maintenance` |
| **Add a new REST endpoint** | `api-design`, `openapi-first-codegen`, `response-layout` (`?layout=`), `response-mapper` (versions / projections), `code-structure` (Pattern C), `exception-handling`, `permissions`, `input-validation`, `unit-tests`, `component-tests` |
| **Add a database table / entity** | `persistence`, `unit-tests`, `integration-tests` |
| **Call an external API** | `external-client`, `resilience-patterns`, `rate-limiting`, `exception-handling`, `observability`, `request-metrics`, `unit-tests`, `integration-tests` |
| **Integrate a swappable technology (cache / DB dialect / metrics backend / broker / secret store)** | `pluggable-architecture`, `adapter-contract-tests`, `spring-boot-conventions`, `observability`, `integration-tests` |
| **Process or publish events** | `messaging`, `code-structure`, `observability`, `unit-tests`, `integration-tests` |
| **Add a background / scheduled task** | `spring-boot-conventions` (§7b), `graceful-shutdown`, `observability`, `unit-tests` |
| **Onboard a legacy service** | `code-structure`, `spring-boot-conventions`, `exception-handling`, `static-analysis`, `health-indicator` |
| **Add a new validation rule** | `input-validation` (apply), `validation-pattern` (background), `exception-handling`, `unit-tests`, `component-tests` |
| **Harden security** | `security-hardening`, `data-privacy`, `permissions`, `local-dev-experience` (secrets) |
| **Improve observability** | `observability`, `request-metrics`, `health-indicator`, `messaging` (DLQ/traceId), `external-client` (decorators) |
| **Add a domain metric for an endpoint** | `request-metrics`, `observability`, `unit-tests` |
| **Publish a shared library (SDK)** | `sdk-publishing`, `api-design`, `documentation-and-adr` |
| **Plan a change / keep it simple** | `golden-path` (apply-order + non-negotiables), `pattern-selection` (smallest pattern that fits), `testable-code-principles`, `strategy-registry-pattern` (runtime-selected behaviour) |
| **Long-running operation / feature toggle** | `async-api-patterns`, `feature-flags` |
| **Refactor large classes** | `refactoring-playbook`, `domain-modeling`, `code-structure` (Patterns A, B, C) |
| **Implement authorization** | `permissions`, `api-design` (URL conventions), `component-tests` |
| **Split work across subagents** | `parallel-delegation`, `unit-tests`, `quality-review` |
| **Prepare a branch for review / cut a release** | `git-commit-conventions`, `quality-review`, `release-versioning`, `ci` |

## How to use this catalogue

1. Locate your **Use Case** in the table above.
2. Read the **Skills** listed in the right column, from left to right.
3. Follow the **Recipes** in `BACKEND_GUILD.md` for specific implementation steps.
4. Use the templates linked in each skill's `Templates` section as a starting point.
5. Apply the **Non-negotiables** from `BACKEND_GUILD.md` §4 to your PR.

## Other languages and cross-cutting tasks

The table above is the Java / Spring Boot map. Install `ai-toolkit-<lang>`; its `*-design` plugin
injects a routing table at session start.

| If you want to… | Python | React Native |
| :--- | :--- | :--- |
| **Structure a new project / module** | `python-code-structure`, `python-fastapi-conventions` | `react-native-code-structure`, `react-native-state-and-data` |
| **Handle errors** | `python-error-handling` | `react-native-error-handling` |
| **Validate input** | `python-input-validation` | `react-native-input-validation` |
| **Persist data / secure the app** | `python-persistence` | `react-native-security` |
| **Write tests** | `python-unit-tests`, `python-integration-tests` | `react-native-unit-tests`, `react-native-e2e-tests` |
| **Lint / typing / static analysis** | `python-static-analysis` | `react-native-static-analysis` |
| **CI and release** | `python-ci` | `react-native-ci` |
| **Logs, traces, crashes** | `python-observability` | `react-native-observability` |

| Any language | Skills |
| :--- | :--- |
| **Finish a task (definition of done)** | `completion-gate`, `code-hygiene`, `sonar-quality-gate` |
| **Commit / PR / release** | `git-commit-conventions`, `pr-description`, `release-versioning` |
| **Split work across subagents** | `parallel-delegation` |
| **Document a decision or system** | `documentation-and-adr`, `uml-diagram`, `context-maintenance` |

# Index by Use Case

This index helps you find the right skills to read based on the task you are performing.

| If you want to... | Read these skills (in order) |
| :--- | :--- |
| **Start a new microservice** | `create-repo`, `ci`, `cd`, `code-structure`, `spring-boot-conventions`, `api-design`, `exception-handling`, `health-indicator`, `observability`, `unit-tests`, `component-tests`, `static-analysis`, `documentation-and-adr`, `context-maintenance` |
| **Add a new REST endpoint** | `api-design`, `openapi-first-codegen`, `code-structure` (Pattern C), `exception-handling`, `permissions`, `input-validation`, `unit-tests`, `component-tests` |
| **Add a database table / entity** | `persistence`, `unit-tests`, `integration-tests` |
| **Call an external API** | `external-client`, `exception-handling`, `observability`, `request-metrics`, `unit-tests`, `integration-tests` |
| **Integrate a swappable technology (cache / DB dialect / metrics backend / broker / secret store)** | `pluggable-architecture`, `adapter-contract-tests`, `spring-boot-conventions`, `observability`, `integration-tests` |
| **Process or publish events** | `messaging`, `code-structure`, `observability`, `unit-tests`, `integration-tests` |
| **Add a background / scheduled task** | `spring-boot-conventions` (§7b), `graceful-shutdown`, `observability`, `unit-tests` |
| **Onboard a legacy service** | `code-structure`, `spring-boot-conventions`, `exception-handling`, `static-analysis`, `health-indicator` |
| **Add a new validation rule** | `input-validation`, `exception-handling`, `unit-tests`, `component-tests` |
| **Harden security** | `security-hardening`, `permissions`, `local-dev-experience` (secrets) |
| **Improve observability** | `observability`, `request-metrics`, `health-indicator`, `messaging` (DLQ/traceId), `external-client` (decorators) |
| **Add a domain metric for an endpoint** | `request-metrics`, `observability`, `unit-tests` |
| **Publish a shared library (SDK)** | `sdk-publishing`, `api-design`, `documentation-and-adr` |
| **Refactor large classes** | `refactoring-playbook`, `domain-modeling`, `code-structure` (Patterns A, B, C) |
| **Implement authorization** | `permissions`, `api-design` (URL conventions), `component-tests` |
| **Prepare a branch for review / cut a release** | `git-commit-conventions`, `quality-review`, `release-versioning`, `ci` |

## How to use this catalogue

1. Locate your **Use Case** in the table above.
2. Read the **Skills** listed in the right column, from left to right.
3. Follow the **Recipes** in `BACKEND_GUILD.md` for specific implementation steps.
4. Use the templates linked in each skill's `Templates` section as a starting point.
5. Apply the **Non-negotiables** from `BACKEND_GUILD.md` §4 to your PR.


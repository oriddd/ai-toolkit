# Copilot Chat Cheatsheet — ai-toolkit Skills

All paths assume `~/.ai-toolkit` is symlinked (run `ln -s /path/to/ai-toolkit ~/.ai-toolkit` once).

---

## Load a single skill

```
#file ~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/exception-handling/SKILL.md
Apply this skill to the current file.
```

Replace `exception-handling` with any skill name from the list below.

---

## Full task — new endpoint

```
#file ~/.ai-toolkit/docs/agents/AGENT_PROMPT.md
#file ~/.ai-toolkit/docs/BACKEND_GUILD.md
#file ~/.ai-toolkit/plugins/ai-toolkit-java-design/skills/api-design/SKILL.md
#file ~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/exception-handling/SKILL.md
#file ~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/input-validation/SKILL.md
Add a POST /orders endpoint that creates an order.
```

## Full task — new downstream service client

```
#file ~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/external-client/SKILL.md
#file ~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/resilience-patterns/SKILL.md
#file ~/.ai-toolkit/plugins/ai-toolkit-java-ops/skills/health-indicator/SKILL.md
Integrate with the Inventory service at http://inventory-svc.
```

## Full task — new Kafka consumer

```
#file ~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/messaging/SKILL.md
#file ~/.ai-toolkit/plugins/ai-toolkit-java-ops/skills/observability/SKILL.md
#file ~/.ai-toolkit/plugins/ai-toolkit-java-ops/skills/graceful-shutdown/SKILL.md
Add a consumer for the orders.created topic.
```

## Full task — new DB entity

```
#file ~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/persistence/SKILL.md
#file ~/.ai-toolkit/plugins/ai-toolkit-java-design/skills/domain-modeling/SKILL.md
Add an Order entity with status, customerId, and createdAt.
```

## Pre-PR code review

```
#file ~/.ai-toolkit/plugins/ai-toolkit-java-quality/skills/quality-review/SKILL.md
#file ~/.ai-toolkit/docs/BACKEND_GUILD.md
Review the current file against the 24 non-negotiables.
```

## Use a task agent (autonomous, picks its own skills)

```
#file ~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/scaffold-repo.md
Create a new Spring Boot service for managing orders.
```

```
#file ~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/new-endpoint.md
Add a PATCH /orders/{id}/status endpoint.
```

```
#file ~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/new-kafka-consumer.md
Add a consumer for the orders.created topic.
```

```
#file ~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/refactor.md
Refactor the OrderService class to align with catalogue patterns.
```

```
#file ~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/code-review.md
Review the changes I just made.
```

```
#file ~/.ai-toolkit/plugins/ai-toolkit-docs/agents/update-context.md
Update the context docs to reflect the new Orders feature.
```

---

## All skills — quick reference

| Skill | Path |
| --- | --- |
| `adapter-contract-tests` | `~/.ai-toolkit/plugins/ai-toolkit-java-quality/skills/adapter-contract-tests/SKILL.md` |
| `api-design` | `~/.ai-toolkit/plugins/ai-toolkit-java-design/skills/api-design/SKILL.md` |
| `async-api-patterns` | `~/.ai-toolkit/plugins/ai-toolkit-java-design/skills/async-api-patterns/SKILL.md` |
| `cd` | `~/.ai-toolkit/plugins/ai-toolkit-java-ops/skills/cd/SKILL.md` |
| `ci` | `~/.ai-toolkit/plugins/ai-toolkit-java-ops/skills/ci/SKILL.md` |
| `code-structure` | `~/.ai-toolkit/plugins/ai-toolkit-java-design/skills/code-structure/SKILL.md` |
| `component-tests` | `~/.ai-toolkit/plugins/ai-toolkit-java-quality/skills/component-tests/SKILL.md` |
| `context-maintenance` | `~/.ai-toolkit/plugins/ai-toolkit-docs/skills/context-maintenance/SKILL.md` |
| `create-repo` | `~/.ai-toolkit/plugins/ai-toolkit-java-scaffold/skills/create-repo/SKILL.md` |
| `data-privacy` | `~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/data-privacy/SKILL.md` |
| `documentation-and-adr` | `~/.ai-toolkit/plugins/ai-toolkit-docs/skills/documentation-and-adr/SKILL.md` |
| `domain-modeling` | `~/.ai-toolkit/plugins/ai-toolkit-java-design/skills/domain-modeling/SKILL.md` |
| `exception-handling` | `~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/exception-handling/SKILL.md` |
| `external-client` | `~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/external-client/SKILL.md` |
| `feature-flags` | `~/.ai-toolkit/plugins/ai-toolkit-java-design/skills/feature-flags/SKILL.md` |
| `github-actions-ci` | `~/.ai-toolkit/plugins/ai-toolkit-java-ops/skills/github-actions-ci/SKILL.md` |
| `graceful-shutdown` | `~/.ai-toolkit/plugins/ai-toolkit-java-ops/skills/graceful-shutdown/SKILL.md` |
| `health-indicator` | `~/.ai-toolkit/plugins/ai-toolkit-java-ops/skills/health-indicator/SKILL.md` |
| `input-validation` | `~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/input-validation/SKILL.md` |
| `integration-tests` | `~/.ai-toolkit/plugins/ai-toolkit-java-quality/skills/integration-tests/SKILL.md` |
| `local-dev-experience` | `~/.ai-toolkit/plugins/ai-toolkit-java-ops/skills/local-dev-experience/SKILL.md` |
| `messaging` | `~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/messaging/SKILL.md` |
| `observability` | `~/.ai-toolkit/plugins/ai-toolkit-java-ops/skills/observability/SKILL.md` |
| `openapi-first-codegen` | `~/.ai-toolkit/plugins/ai-toolkit-java-design/skills/openapi-first-codegen/SKILL.md` |
| `permissions` | `~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/permissions/SKILL.md` |
| `persistence` | `~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/persistence/SKILL.md` |
| `pluggable-architecture` | `~/.ai-toolkit/plugins/ai-toolkit-java-design/skills/pluggable-architecture/SKILL.md` |
| `project-types` | `~/.ai-toolkit/plugins/ai-toolkit-java-scaffold/skills/project-types/SKILL.md` |
| `quality-review` | `~/.ai-toolkit/plugins/ai-toolkit-java-quality/skills/quality-review/SKILL.md` |
| `rate-limiting` | `~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/rate-limiting/SKILL.md` |
| `refactoring-playbook` | `~/.ai-toolkit/plugins/ai-toolkit-java-quality/skills/refactoring-playbook/SKILL.md` |
| `release-versioning` | `~/.ai-toolkit/plugins/ai-toolkit-workflow/skills/release-versioning/SKILL.md` |
| `request-metrics` | `~/.ai-toolkit/plugins/ai-toolkit-java-ops/skills/request-metrics/SKILL.md` |
| `resilience-patterns` | `~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/resilience-patterns/SKILL.md` |
| `sdk-publishing` | `~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/sdk-publishing/SKILL.md` |
| `security-hardening` | `~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/security-hardening/SKILL.md` |
| `spring-boot-conventions` | `~/.ai-toolkit/plugins/ai-toolkit-java-design/skills/spring-boot-conventions/SKILL.md` |
| `static-analysis` | `~/.ai-toolkit/plugins/ai-toolkit-java-quality/skills/static-analysis/SKILL.md` |
| `uml-diagram` | `~/.ai-toolkit/plugins/ai-toolkit-docs/skills/uml-diagram/SKILL.md` |
| `unit-tests` | `~/.ai-toolkit/plugins/ai-toolkit-java-quality/skills/unit-tests/SKILL.md` |

## All Java agents — quick reference

| Agent | Path |
| --- | --- |
| `scaffold-repo` | `~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/scaffold-repo.md` |
| `new-endpoint` | `~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/new-endpoint.md` |
| `new-feature` | `~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/new-feature.md` |
| `new-kafka-consumer` | `~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/new-kafka-consumer.md` |
| `new-microservice-client` | `~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/new-microservice-client.md` |
| `new-validation` | `~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/new-validation.md` |
| `new-metric` | `~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/new-metric.md` |
| `code-review` | `~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/code-review.md` |
| `refactor` | `~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/refactor.md` |
| `update-context` | `~/.ai-toolkit/plugins/ai-toolkit-docs/agents/update-context.md` |


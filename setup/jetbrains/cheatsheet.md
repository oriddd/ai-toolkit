# Copilot Chat Cheatsheet — ai-toolkit Skills

All paths assume `~/.ai-toolkit` is symlinked (run `ln -s /Users/odafna/repo/oriddd/ai-toolkit ~/.ai-toolkit` once).

---

## Load a single skill

```
#file ~/.ai-toolkit/copilot/public/skills/exception-handling/SKILL.md
Apply this skill to the current file.
```

Replace `exception-handling` with any skill name from the list below.

---

## Full task — new endpoint

```
#file ~/.ai-toolkit/copilot/public/agents/AGENT_PROMPT.md
#file ~/.ai-toolkit/copilot/public/skills/BACKEND_GUILD.md
#file ~/.ai-toolkit/copilot/public/skills/api-design/SKILL.md
#file ~/.ai-toolkit/copilot/public/skills/exception-handling/SKILL.md
#file ~/.ai-toolkit/copilot/public/skills/input-validation/SKILL.md
Add a POST /orders endpoint that creates an order.
```

## Full task — new downstream service client

```
#file ~/.ai-toolkit/copilot/public/skills/external-client/SKILL.md
#file ~/.ai-toolkit/copilot/public/skills/resilience-patterns/SKILL.md
#file ~/.ai-toolkit/copilot/public/skills/health-indicator/SKILL.md
Integrate with the Inventory service at http://inventory-svc.
```

## Full task — new Kafka consumer

```
#file ~/.ai-toolkit/copilot/public/skills/messaging/SKILL.md
#file ~/.ai-toolkit/copilot/public/skills/observability/SKILL.md
#file ~/.ai-toolkit/copilot/public/skills/graceful-shutdown/SKILL.md
Add a consumer for the orders.created topic.
```

## Full task — new DB entity

```
#file ~/.ai-toolkit/copilot/public/skills/persistence/SKILL.md
#file ~/.ai-toolkit/copilot/public/skills/domain-modeling/SKILL.md
Add an Order entity with status, customerId, and createdAt.
```

## Pre-PR code review

```
#file ~/.ai-toolkit/copilot/public/skills/quality-review/SKILL.md
#file ~/.ai-toolkit/copilot/public/skills/BACKEND_GUILD.md
Review the current file against the 24 non-negotiables.
```

## Use a task agent (autonomous, picks its own skills)

```
#file ~/.ai-toolkit/copilot/public/agents/scaffold-repo.md
Create a new Spring Boot service for managing orders.
```

```
#file ~/.ai-toolkit/copilot/public/agents/new-endpoint.md
Add a PATCH /orders/{id}/status endpoint.
```

```
#file ~/.ai-toolkit/copilot/public/agents/new-kafka-consumer.md
Add a consumer for the orders.created topic.
```

```
#file ~/.ai-toolkit/copilot/public/agents/refactor.md
Refactor the OrderService class to align with catalogue patterns.
```

```
#file ~/.ai-toolkit/copilot/public/agents/code-review.md
Review the changes I just made.
```

```
#file ~/.ai-toolkit/copilot/public/agents/update-context.md
Update the context docs to reflect the new Orders feature.
```

---

## All 40 skills — quick reference

| Skill | Path |
| --- | --- |
| `adapter-contract-tests` | `~/.ai-toolkit/copilot/public/skills/adapter-contract-tests/SKILL.md` |
| `api-design` | `~/.ai-toolkit/copilot/public/skills/api-design/SKILL.md` |
| `async-api-patterns` | `~/.ai-toolkit/copilot/public/skills/async-api-patterns/SKILL.md` |
| `cd` | `~/.ai-toolkit/copilot/public/skills/cd/SKILL.md` |
| `ci` | `~/.ai-toolkit/copilot/public/skills/ci/SKILL.md` |
| `code-structure` | `~/.ai-toolkit/copilot/public/skills/code-structure/SKILL.md` |
| `component-tests` | `~/.ai-toolkit/copilot/public/skills/component-tests/SKILL.md` |
| `context-maintenance` | `~/.ai-toolkit/copilot/public/skills/context-maintenance/SKILL.md` |
| `create-repo` | `~/.ai-toolkit/copilot/public/skills/create-repo/SKILL.md` |
| `data-privacy` | `~/.ai-toolkit/copilot/public/skills/data-privacy/SKILL.md` |
| `documentation-and-adr` | `~/.ai-toolkit/copilot/public/skills/documentation-and-adr/SKILL.md` |
| `domain-modeling` | `~/.ai-toolkit/copilot/public/skills/domain-modeling/SKILL.md` |
| `exception-handling` | `~/.ai-toolkit/copilot/public/skills/exception-handling/SKILL.md` |
| `external-client` | `~/.ai-toolkit/copilot/public/skills/external-client/SKILL.md` |
| `feature-flags` | `~/.ai-toolkit/copilot/public/skills/feature-flags/SKILL.md` |
| `github-actions-ci` | `~/.ai-toolkit/copilot/public/skills/github-actions-ci/SKILL.md` |
| `graceful-shutdown` | `~/.ai-toolkit/copilot/public/skills/graceful-shutdown/SKILL.md` |
| `health-indicator` | `~/.ai-toolkit/copilot/public/skills/health-indicator/SKILL.md` |
| `input-validation` | `~/.ai-toolkit/copilot/public/skills/input-validation/SKILL.md` |
| `integration-tests` | `~/.ai-toolkit/copilot/public/skills/integration-tests/SKILL.md` |
| `local-dev-experience` | `~/.ai-toolkit/copilot/public/skills/local-dev-experience/SKILL.md` |
| `messaging` | `~/.ai-toolkit/copilot/public/skills/messaging/SKILL.md` |
| `observability` | `~/.ai-toolkit/copilot/public/skills/observability/SKILL.md` |
| `openapi-first-codegen` | `~/.ai-toolkit/copilot/public/skills/openapi-first-codegen/SKILL.md` |
| `permissions` | `~/.ai-toolkit/copilot/public/skills/permissions/SKILL.md` |
| `persistence` | `~/.ai-toolkit/copilot/public/skills/persistence/SKILL.md` |
| `pluggable-architecture` | `~/.ai-toolkit/copilot/public/skills/pluggable-architecture/SKILL.md` |
| `project-types` | `~/.ai-toolkit/copilot/public/skills/project-types/SKILL.md` |
| `quality-review` | `~/.ai-toolkit/copilot/public/skills/quality-review/SKILL.md` |
| `rate-limiting` | `~/.ai-toolkit/copilot/public/skills/rate-limiting/SKILL.md` |
| `refactoring-playbook` | `~/.ai-toolkit/copilot/public/skills/refactoring-playbook/SKILL.md` |
| `release-versioning` | `~/.ai-toolkit/copilot/public/skills/release-versioning/SKILL.md` |
| `request-metrics` | `~/.ai-toolkit/copilot/public/skills/request-metrics/SKILL.md` |
| `resilience-patterns` | `~/.ai-toolkit/copilot/public/skills/resilience-patterns/SKILL.md` |
| `sdk-publishing` | `~/.ai-toolkit/copilot/public/skills/sdk-publishing/SKILL.md` |
| `security-hardening` | `~/.ai-toolkit/copilot/public/skills/security-hardening/SKILL.md` |
| `spring-boot-conventions` | `~/.ai-toolkit/copilot/public/skills/spring-boot-conventions/SKILL.md` |
| `static-analysis` | `~/.ai-toolkit/copilot/public/skills/static-analysis/SKILL.md` |
| `uml-diagram` | `~/.ai-toolkit/copilot/public/skills/uml-diagram/SKILL.md` |
| `unit-tests` | `~/.ai-toolkit/copilot/public/skills/unit-tests/SKILL.md` |

## All 10 agents — quick reference

| Agent | Path |
| --- | --- |
| `scaffold-repo` | `~/.ai-toolkit/copilot/public/agents/scaffold-repo.md` |
| `new-endpoint` | `~/.ai-toolkit/copilot/public/agents/new-endpoint.md` |
| `new-feature` | `~/.ai-toolkit/copilot/public/agents/new-feature.md` |
| `new-kafka-consumer` | `~/.ai-toolkit/copilot/public/agents/new-kafka-consumer.md` |
| `new-microservice-client` | `~/.ai-toolkit/copilot/public/agents/new-microservice-client.md` |
| `new-validation` | `~/.ai-toolkit/copilot/public/agents/new-validation.md` |
| `new-metric` | `~/.ai-toolkit/copilot/public/agents/new-metric.md` |
| `code-review` | `~/.ai-toolkit/copilot/public/agents/code-review.md` |
| `refactor` | `~/.ai-toolkit/copilot/public/agents/refactor.md` |
| `update-context` | `~/.ai-toolkit/copilot/public/agents/update-context.md` |


# Copilot Chat Cheatsheet — ai-toolkit Skills

All paths assume `~/.ai-toolkit` is symlinked (run `ln -sfn /path/to/ai-toolkit ~/.ai-toolkit` once).

---

## Load a single skill

```
#file ~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/exception-handling/SKILL.md
Apply this skill to the current file.
```

Replace `exception-handling` with any skill name from [`docs/REGISTRY.md`](../../docs/REGISTRY.md); a skill lives at
`~/.ai-toolkit/plugins/<plugin>/skills/<skill>/SKILL.md`. The largest Java skills keep their code in `references/*.md` next to `SKILL.md` —
`#file` the relevant reference file too, or Copilot only sees the reference map.

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

## All skills

The complete, generated list is [`docs/REGISTRY.md`](../../docs/REGISTRY.md). Every skill is at
`~/.ai-toolkit/plugins/<plugin>/skills/<skill>/SKILL.md`.

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


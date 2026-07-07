# Agents Cheatsheet

Pro tips for **using and authoring agents** — the task-focused prompts that
compose skills for a single job. (Sits next to the agents it serves.)

---

## Using an agent

An agent is a ready-made system prompt. Load it, then state your task:

```
#file ~/.ai-toolkit/copilot/public/agents/new-endpoint.md
Add a PATCH /orders/{id}/status endpoint.
```

For a full autonomous run, pair the general operating manual with a topic agent:

```
#file ~/.ai-toolkit/copilot/public/agents/AGENT_PROMPT.md
#file ~/.ai-toolkit/copilot/public/agents/scaffold-repo.md
Create a new Spring Boot service for managing orders.
```

## The 10 agents

| Agent | Use when… |
| --- | --- |
| `scaffold-repo` | Creating a brand-new Spring Boot service from scratch |
| `new-endpoint` | Adding a REST endpoint |
| `new-feature` | Implementing a multi-layer feature end-to-end |
| `new-kafka-consumer` | Adding a Kafka consumer (idempotent, DLQ, observability) |
| `new-microservice-client` | Integrating a new downstream service |
| `new-validation` | Adding an input-validation rule |
| `new-metric` | Adding a domain request metric |
| `code-review` | Pre-PR quality review against the non-negotiables |
| `refactor` | Migrating legacy code to canonical patterns |
| `update-context` | Updating docs / CHANGELOG after a change |

---

## Authoring an agent

An agent is **not** a skill — it is a thin orchestrator that points at the
skills to apply, in order. Rules of thumb:

1. **Stay under ~80 lines.** If it grows, the logic belongs in a skill.
2. **Reference, don't duplicate.** Link skills with `../skills/<name>/SKILL.md`;
   never paste a skill's rules into the agent.
3. **One task per agent.** If you find yourself branching heavily, split it.
4. **Standard shape:** Purpose → Skills to apply (ordered) → Step-by-step
   procedure → Checklist before returning.
5. **Add a row** to [`README.md`](./README.md) so the agent is discoverable.

Template skeleton:

```markdown
# Agent: <Task Name>

> **Purpose:** one sentence.

## Skills to apply (in this order)
1. [`<skill>`](../skills/<skill>/SKILL.md) — why.
2. …

## Step-by-step procedure
```
1. CLARIFY (only if missing): …
2. GENERATE (in order): …
3. TEST: …
4. CONTEXT: update context/ + CHANGELOG.
```

## Checklist before returning
- [ ] …
```

## Relationship to the general prompt

[`AGENT_PROMPT.md`](./AGENT_PROMPT.md) is the always-on operating manual
(read order, decision algorithm, the 24 non-negotiables, output expectations).
Topic agents **extend** it — drop a topic agent in addition to, or instead of,
the general prompt when you already know the task.


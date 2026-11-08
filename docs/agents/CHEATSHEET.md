# Agents Cheatsheet

Pro tips for **using and authoring agents** — the task-focused prompts that
compose skills for a single job. (Sits next to the agents it serves.)

---

## Using an agent

Install `ai-toolkit-java-agents` together with the skill plugins it composes — the Java skill plugins,
`ai-toolkit-quality` (completion gate, code hygiene), `ai-toolkit-workflow` (commit policy, delegation) and
`ai-toolkit-docs` (`update-context`). Install them explicitly; do not rely on them arriving as dependencies.

Agents that ask the developer questions (CLARIFY / confirm steps, HITL skills) work best as the
**main-session agent**, because a subagent cannot ask anything:

```bash
claude --agent ai-toolkit-java-agents:new-endpoint
```

Each agent is also available as a Claude Code subagent — name it in your request. As a subagent it returns
`NEEDS INPUT:` with its open questions instead of guessing; answer them and ask again:

```
Use the new-endpoint agent to add a PATCH /orders/{id}/status endpoint.
```

For other tools (Cursor, Copilot, …) paste `docs/agents/AGENT_PROMPT.md` plus
the agent file from `plugins/ai-toolkit-java-agents/agents/` into the system prompt.

### GitHub Copilot / other tools (`#file`)

An agent is a ready-made system prompt. Load it, then state your task:

```
#file ~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/new-endpoint.md
Add a PATCH /orders/{id}/status endpoint.
```

For a full autonomous run, pair the general operating manual with a topic agent:

```
#file ~/.ai-toolkit/docs/agents/AGENT_PROMPT.md
#file ~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/scaffold-repo.md
Create a new Spring Boot service for managing orders.
```

## The Java agents (10, plus `update-context` from `ai-toolkit-docs`)

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
| `test-writer` | Writing tests for classes that already exist (the worker the other agents delegate to) |
| `update-context` (`ai-toolkit-docs`) | Updating docs / CHANGELOG after a change |

Other plugins: `ai-toolkit-python-agents` (5) and `ai-toolkit-react-native-agents` (5) — see [`README.md`](./README.md).

---

## Authoring an agent

An agent is **not** a skill — it is a thin orchestrator that points at the
skills to apply, in order. Rules of thumb:

1. **Stay short** — ~40–80 lines for a worker or reviewer; orchestrators with delegation and gate blocks reach
   ~170. If it grows beyond that, the logic belongs in a skill.
2. **Reference, don't duplicate.** Reference skills by name in backticks (relative links between plugins break when plugins are installed separately);
   never paste a skill's rules into the agent.
3. **One task per agent.** If you find yourself branching heavily, split it.
4. **Standard shape:** frontmatter → Purpose → Skills to apply (ordered, qualified names) → Step-by-step
   procedure → Questions as a subagent → Delegation → Commit policy and completion gate → Checklist before returning.
   Review agents declare read-only `tools:`; code-writing agents must run `completion-gate` and never commit.
5. **Add a row** to [`README.md`](./README.md) so the agent is discoverable.

Template skeleton:

```markdown
---
name: <agent-name>
description: <Language / framework> — what it does. Use when …
tools: Read, Grep, Glob, Bash, Skill   # review agents only; code-writing agents inherit all tools
---

# Agent: <Task Name>

> **Purpose:** one sentence.

## Skills to apply (in this order)
Load each skill with the Skill tool, by its qualified name, before applying it.
1. `<plugin>:<skill>` — why.
2. …

## Step-by-step procedure
```
1. CLARIFY (only if missing): …
2. GENERATE (in order): …
3. TEST: …
4. CONTEXT: update context/ + CHANGELOG (only when no release bot owns it).
```

## Questions when you run as a subagent
A subagent cannot ask the developer: with open questions, write no files and return
`NEEDS INPUT:` with the questions and proposed defaults.

## Delegation (use subagents when you can)
Follow `ai-toolkit-workflow:parallel-delegation`; fan out only independent work, once the code it
depends on exists. Briefs say: no builds or tests, never stage, commit, push or stash.

## Commit policy and completion gate
Never commit, push, stash or tag. Run `ai-toolkit-quality:completion-gate` and return its evidence table.

## Checklist before returning
- [ ] …
- [ ] `ai-toolkit-quality:completion-gate` evidence table produced; nothing committed.
```

## Relationship to the general prompt

[`AGENT_PROMPT.md`](./AGENT_PROMPT.md) is the always-on operating manual
(read order, decision algorithm, the 24 non-negotiables, output expectations).
Topic agents **extend** it — drop a topic agent in addition to, or instead of,
the general prompt when you already know the task.


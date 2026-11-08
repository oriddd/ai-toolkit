# Agents

Topic-specific agent prompts that extend the general
[`AGENT_PROMPT.md`](./AGENT_PROMPT.md). Each agent is pre-loaded with
the exact skill subset needed for a single, focused task. Drop the
relevant agent file into your AI tool's system prompt **in addition to**
(or instead of) the general prompt when you know up front what you're
building.

| Agent | Use when… |
| --- | --- |
| [`test-writer.md`](../../plugins/ai-toolkit-java-agents/agents/test-writer.md) | Worker: unit, component and integration (`*IT`) tests for existing classes — run in parallel by the other agents |
| [`scaffold-repo.md`](../../plugins/ai-toolkit-java-agents/agents/scaffold-repo.md) | Creating a brand-new Spring Boot service repository from scratch |
| [`new-endpoint.md`](../../plugins/ai-toolkit-java-agents/agents/new-endpoint.md) | Adding a REST endpoint to an existing service |
| [`new-feature.md`](../../plugins/ai-toolkit-java-agents/agents/new-feature.md) | Implementing a multi-layer feature end-to-end |
| [`new-kafka-consumer.md`](../../plugins/ai-toolkit-java-agents/agents/new-kafka-consumer.md) | Adding a Kafka consumer with idempotency, DLQ, and observability |
| [`new-microservice-client.md`](../../plugins/ai-toolkit-java-agents/agents/new-microservice-client.md) | Integrating a new downstream microservice or external API |
| [`new-validation.md`](../../plugins/ai-toolkit-java-agents/agents/new-validation.md) | Adding a new input-validation rule (Jakarta or Spring Validator) |
| [`new-metric.md`](../../plugins/ai-toolkit-java-agents/agents/new-metric.md) | Adding a domain request metric for an endpoint |
| [`code-review.md`](../../plugins/ai-toolkit-java-agents/agents/code-review.md) | Pre-PR quality review against all non-negotiables |
| [`refactor.md`](../../plugins/ai-toolkit-java-agents/agents/refactor.md) | Migrating legacy code to canonical catalogue patterns |
| [`update-context.md`](../../plugins/ai-toolkit-docs/agents/update-context.md) | Updating architecture docs, CHANGELOG, progress tracker, or any `context/` file |

**Also here:** [`AGENT_PROMPT.md`](./AGENT_PROMPT.md) (the general operating manual)
and [`CHEATSHEET.md`](./CHEATSHEET.md) (using & authoring agents).


## Working with subagents

The orchestrating agents (`new-feature`, `new-endpoint`, `new-kafka-consumer`, `new-microservice-client`,
`refactor`, `scaffold-repo`) fan independent work out to `test-writer`, `update-context`, `code-review` and
`general-purpose` subagents (see the `parallel-delegation` skill) whenever the Agent tool is available — a subagent
can start subagents too. Without it, or pasted into another tool, the same steps run inline. `code-review` is read-only.

**Questions need the main session.** A subagent cannot ask the developer anything. Run an orchestrator that must
ask (CLARIFY / confirm steps, HITL skills) as the main-session agent:

```bash
claude --agent ai-toolkit-java-agents:new-endpoint
```

Invoked as a subagent, an orchestrator with open questions writes nothing and returns `NEEDS INPUT:` with its
questions and proposed defaults; the caller asks the developer and invokes it again with the answers.
`scaffold-repo` is HITL throughout — run it only with `claude --agent ai-toolkit-java-agents:scaffold-repo`.

## Other languages

| Plugin | Agents |
| --- | --- |
| `ai-toolkit-python-agents` | `python-new-endpoint`, `python-new-feature`, `python-refactor`, `python-code-review`, `python-test-writer` |
| `ai-toolkit-react-native-agents` | `react-native-new-screen`, `react-native-new-feature`, `react-native-refactor`, `react-native-code-review`, `react-native-test-writer` |
| `ai-toolkit-docs` | `update-context` (any language) |

Invoke the same way, e.g. `claude --agent ai-toolkit-python-agents:python-new-endpoint`. Code-writing agents never commit and finish with the `completion-gate` evidence table.

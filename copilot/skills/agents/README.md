# Agents

Topic-specific agent prompts that extend the general
[`AGENT_PROMPT.md`](../AGENT_PROMPT.md). Each agent is pre-loaded with
the exact skill subset needed for a single, focused task. Drop the
relevant agent file into your AI tool's system prompt **in addition to**
(or instead of) the general prompt when you know up front what you're
building.

| Agent | Use when… |
| --- | --- |
| [`update-context.md`](./update-context.md) | Updating architecture docs, CHANGELOG, progress tracker, or any `context/` file |
| [`new-endpoint.md`](./new-endpoint.md) | Adding a REST endpoint to an existing service |
| [`new-microservice-client.md`](./new-microservice-client.md) | Integrating a new downstream microservice or external API |
| [`new-validation.md`](./new-validation.md) | Adding a new input-validation rule (Jakarta or Spring Validator) |
| [`new-metric.md`](./new-metric.md) | Adding a domain request metric for an endpoint |
| [`code-review.md`](./code-review.md) | Pre-PR quality review against all non-negotiables |
| [`new-feature.md`](./new-feature.md) | Implementing a multi-layer feature end-to-end |


# Messaging Skill — Schema management

Part of the [`messaging`](../SKILL.md) skill. Headings are stable; other skills cite them.

## 2. Schema management

| Format | Use when |
| --- | --- |
| **Avro + Schema Registry** | Strict schema evolution, long-lived events, large fanout. |
| **Protobuf** | Polyglot consumers (Go/Rust), gRPC nearby. |
| **JSON Schema** | Small org, no schema registry, accept evolution risk. |

Rules:
- Schemas are **forward + backward compatible** during normal evolution. A
  consumer must be able to consume yesterday's event; a producer must be
  able to produce today's event without breaking yesterday's consumer.
- Add fields with **defaults**; never remove required fields without a major
  version bump.
- Schemas live in `messaging/schemas/` and are published as a separate
  artifact (see `sdk-publishing`) so cross-team consumers can depend on a
  versioned jar.

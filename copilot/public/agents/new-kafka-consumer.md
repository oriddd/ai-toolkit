# Agent: New Kafka Consumer

> **Purpose:** Add a fully production-ready Kafka consumer to an existing
> Spring Boot service — idempotency, DLQ, outbox (if needed), observability,
> graceful shutdown, and tests.

---

You are a backend-coding agent for a Java 21 / Spring Boot microservice.
The developer wants to **add a new Kafka consumer**. You will produce every
file change needed, satisfying all messaging non-negotiables.

## Skills to apply (in this order)

1. [`messaging`](../skills/messaging/SKILL.md) — idempotent consumer,
   DLQ wiring, transactional outbox pattern, Kafka config.
2. [`pluggable-architecture`](../skills/pluggable-architecture/SKILL.md) —
   broker dependency behind a port; vendor SDK only inside the adapter.
3. [`observability`](../skills/observability/SKILL.md) — MDC correlation ID
   from message header, consumer lag metric, structured logging.
4. [`graceful-shutdown`](../skills/graceful-shutdown/SKILL.md) — consumer
   group paused before pod termination; in-flight message drained.
5. [`exception-handling`](../skills/exception-handling/SKILL.md) — domain
   exception subclass for consumer failures + `ExceptionMessages` entry.
6. [`unit-tests`](../skills/unit-tests/SKILL.md) — consumer + idempotency
   guard + any outbox service.
7. [`integration-tests`](../skills/integration-tests/SKILL.md) — Testcontainers
   Kafka; publish a message, assert side effects.

## Step-by-step procedure

```
1. CLARIFY (only if missing):
   - Topic name and partition strategy
   - Message key/value schema (Avro / JSON / plain string)
   - Consumer group ID
   - Idempotency key (which field uniquely identifies a message?)
   - Expected side effect (persist entity / call downstream / publish event)
   - Does a failure need an outbox? (at-least-once vs exactly-once)

2. DESIGN:
   - Consumer class name + package (event/consumer/)
   - Idempotency store (DB column / Redis key / in-memory for tests)
   - DLQ topic naming convention
   Confirm with developer before generating.

3. GENERATE (in order):
   a. KafkaConfig — consumer factory, concurrency, DLQ RetryTopicConfiguration.
   b. Consumer class — @KafkaListener, idempotency guard, delegates to *Service.
   c. Idempotency record/entity + repository (if DB-backed).
   d. *Service — business logic, @Transactional.
   e. Outbox entity + publisher (if at-least-once delivery required).
   f. ObservabilityConfig additions — MDC header propagator, consumer lag gauge.
   g. Graceful-shutdown hook — consumer.pause() on SIGTERM.
   h. application.yaml additions — topic, group-id, DLQ topic, concurrency.

4. TEST:
   a. Unit tests — consumer (mock service), idempotency guard (duplicate input).
   b. Integration test — Testcontainers Kafka; produce → consume → assert DB state.

5. CONTEXT:
   - Update context/architecture.md (new event consumer + topic).
   - Update context/dependencies.md (Kafka broker entry if new).
   - Append to CHANGELOG.md [Unreleased].
```

## Checklist before returning

- [ ] Consumer is idempotent — duplicate message produces identical outcome.
- [ ] DLQ is wired (`@RetryableTopic` or `DeadLetterPublishingRecoverer`).
- [ ] MDC correlation ID propagated from message header.
- [ ] Consumer paused on graceful shutdown; in-flight message completes.
- [ ] Kafka config uses `@ConfigurationProperties` — no hard-coded values.
- [ ] Broker dependency is behind a port (pluggable-architecture).
- [ ] Unit test covers duplicate-message idempotency path.
- [ ] Integration test uses Testcontainers Kafka (no mocked broker).
- [ ] CHANGELOG updated.


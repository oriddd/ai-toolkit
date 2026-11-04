---
name: messaging
description: Wire async messaging (Kafka or RabbitMQ) into a Spring Boot service with the canonical patterns — idempotent consumer, transactional outbox for producer-side atomicity, dead-letter topic with redelivery policy, schema management (Avro/Protobuf/JSON-Schema), consumer concurrency, exactly-once semantics. Use whenever a service publishes or consumes domain events or commands.
tier: should
applies_to: [event, monolith]
depends_on: [code-structure, observability, pluggable-architecture]
ships_templates: true
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Messaging Skill
Async messaging requires more discipline than sync HTTP. This skill captures
the **non-negotiable** patterns; the broker choice is secondary.

```
src/main/java/<basePackage>/
├── event/               # immutable event records — the contract
├── messaging/
│   ├── producer/        # publishers (use transactional outbox)
│   ├── consumer/        # @KafkaListener / @RabbitListener
│   └── outbox/          # outbox table writer + relay
└── operation/           # use-case orchestrators (publish events as side-effects)
```

## 1. Events as immutable records

```java
public record InvoiceCreatedEvent(
        String invoiceId,
        String name,
        Instant occurredAt,
        String traceId) implements DomainEvent {}
```

- **Always a record**, always immutable.
- Always contains: a `traceId` (propagated from the originating request),
  an `occurredAt` timestamp, and the **business identifiers** of the
  aggregate affected.
- **Never** put internal database row IDs into events — use the
  application-assigned aggregate ID.

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

## 3. Producer — transactional outbox

The naïve pattern "save row + publish event" is **wrong** — the publish can
succeed and the DB commit fail, or vice-versa.

Canonical pattern:

```
┌──────────┐  same DB tx  ┌──────────┐
│  service │ ───────────► │  outbox  │
└──────────┘              └────┬─────┘
                               │ async relay
                               ▼
                          ┌──────────┐
                          │  broker  │
                          └──────────┘
```

Implementation:

```java
@Service
public class InvoiceService {
    @Transactional
    public Invoice create(CreateRequest req) {
        var invoice = new Invoice(req.id(), req.name());
        invoiceRepo.save(invoice);
        outbox.append(new InvoiceCreatedEvent(invoice.getId(), invoice.getName(), now(), traceId()));
        return invoice;
    }
}

@Component
public class OutboxRelay {
    @Scheduled(fixedDelayString = "${outbox.relay.delay:200ms}")      // property-driven, never a literal
    @Transactional
    public void publishPending() {
        // FOR UPDATE SKIP LOCKED: several instances can run the relay without publishing the same row twice
        outboxRepo.fetchPendingForUpdateSkipLocked(100).forEach(row -> {
            kafkaTemplate.send(row.topic(), row.key(), row.payload()).join();   // wait for the broker ack before marking
            row.markPublished();
        });
    }
}
```

- A dedicated `outbox` table in the same DB as the entity.
- A `@Scheduled` (or **Debezium CDC** for high throughput) relay polls
  unpublished rows (`publishedAt IS NULL`) and publishes them, setting `publishedAt` only after the broker has acknowledged the send.
- The relay is **idempotent**: if the broker accepts the event but the
  mark-as-sent fails, the next tick re-publishes it. Consumers must handle
  this (see below).

### Outbox Performance & Clean-up

For high-throughput services, the outbox table can grow rapidly:
1. **Indexes**: Ensure `publishedAt` (a partial index on the unpublished rows works well) and `createdAt` are indexed.
2. **Partitioning**: Consider Postgres table partitioning by `createdAt` (e.g., one partition per day).
3. **Retention**: Run a background job to delete records published more than 7 days ago.
4. **Batching**: The relay should fetch and publish in batches of 100-500 to minimize overhead.

## 4. Consumer — idempotent + at-least-once

Brokers guarantee at-least-once. The consumer must be **idempotent**:

```java
@Component
@RequiredArgsConstructor
public class InvoiceCreatedConsumer {

    private final ProcessedEventRepository processed;
    private final FooService service;

    @KafkaListener(topics = "invoices", groupId = "foo-service")
    public void on(ConsumerRecord<String, InvoiceCreatedEvent> rec, Acknowledgment ack) {
        var eventId = new String(rec.headers().lastHeader("event-id").value(), StandardCharsets.UTF_8);
        service.handleOnce(eventId, rec.value());   // @Transactional: dedupe insert + business effect commit together
        ack.acknowledge();                          // only after the transaction committed
    }
}

@Service
public class FooService {
    @Transactional
    public void handleOnce(String eventId, InvoiceCreatedEvent event) {
        if (!processed.tryRecord(eventId)) {
            return;                                 // already handled — skip
        }
        handle(event);
    }
}
```

- Every event carries a unique **event-id** header (UUID).
- `processed.tryRecord(eventId)` returns `false` if the row already exists
  (`INSERT ... ON CONFLICT DO NOTHING`).
- The consumer's business transaction includes the `processed` insert, so
  effects are atomic with the dedupe record.
- Use **manual ack** + **at-least-once**; commit offset only after the
  business transaction commits.

## 5. Dead-letter topic

After **N retries** with exponential backoff, send to a `<topic>-dlt` (Spring Kafka's default suffix) and
emit a **metric + alert** so an operator notices. Default values (Spring Boot 3.2+ non-blocking retry topics):

```yaml
spring:
  kafka:
    listener:
      ack-mode: manual
      concurrency: 3
      missing-topics-fatal: false
    retry:
      topic:
        enabled: true
        attempts: 5
        delay: 1s
        multiplier: 2
        max-delay: 30s
```

A DLT record carries `kafka_dlt-exception-fqcn`, `kafka_dlt-exception-message` and `kafka_dlt-original-topic` headers explaining the failure. A redrive
operator tool replays from DLT after a fix.

## 6. Concurrency & ordering

- **Partition key = aggregate id.** Guarantees in-order processing per
  aggregate; allows parallelism across aggregates.
- Consumer concurrency ≤ partition count.
- **Never** assume cross-partition ordering. If you need it, redesign.

## 7. Testing

- **Unit tests** stub the broker via Spring's `EmbeddedKafkaBroker` or a
  pure Mockito mock of the producer interface.
- **Integration tests** use a **Testcontainer** (`KafkaContainer` /
  `RabbitMQContainer`) — see `integration-tests`.
- The outbox relay is unit-tested with a fake clock; the at-least-once
  consumer is integration-tested by publishing the same event twice and
  asserting one effect.

## Do / Don't

✅ Events are records; producer uses transactional outbox; consumer is
idempotent; partition key = aggregate id; DLT after N retries.
✅ Schemas are versioned and compatibility-checked in CI.
❌ Never publish from inside an HTTP handler without going through the outbox
("save then publish" race).
❌ Never block a consumer thread on a sync HTTP call to a slow downstream —
hand off to a `@Async` executor with backpressure.
❌ Never use messaging for request/response. Use HTTP or gRPC.

## 8. Templates

- [`KafkaConfig.java.tmpl`](./templates/KafkaConfig.java.tmpl) — Baseline Kafka producer/consumer configuration.
- [`IdempotentConsumer.java.tmpl`](./templates/IdempotentConsumer.java.tmpl) — Pattern for deduplicating incoming events.
- [`OutboxEntity.java.tmpl`](./templates/OutboxEntity.java.tmpl) — Database entity for the Transactional Outbox.
- [`DlqHandler.java.tmpl`](./templates/DlqHandler.java.tmpl) — Standard Dead Letter Queue processing.

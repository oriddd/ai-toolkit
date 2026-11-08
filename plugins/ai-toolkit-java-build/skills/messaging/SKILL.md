---
name: messaging
description: >
  Java / Spring Boot Kafka or RabbitMQ — idempotent consumer, transactional outbox, dead-letter topic and redelivery,
  schema management (Avro/Protobuf/JSON-Schema), concurrency, exactly-once scope. Use when a service publishes or
  consumes events or commands.
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
        Instant occurredAt) implements DomainEvent {}
```

- **Always a record**, always immutable.
- Always contains: an `occurredAt` timestamp and the **business identifiers**
  of the aggregate affected. The trace is **not** an event field: it travels
  as the W3C `traceparent` record header (`observability` — never invent a
  correlation field). Turn on `spring.kafka.template.observation-enabled` and
  `spring.kafka.listener.observation-enabled`; the outbox stores the
  originating `traceparent` and the relay sends it as a header (§3).
- **No PII in events.** Carry ids and non-personal business facts; a
  consumer that needs personal data fetches it from the owner. Outbox rows
  and topic retention keep payloads long after a right-to-be-forgotten
  request (`data-privacy` §4); if PII is unavoidable, encrypt it with a
  per-subject key and delete the key to forget (crypto-shredding).
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
        outbox.append(new InvoiceCreatedEvent(invoice.getId(), invoice.getName(), now()));  // also stores the current traceparent
        return invoice;
    }
}

@Component
@RequiredArgsConstructor
@Slf4j
public class OutboxRelay {
    private final OutboxRepository outboxRepo;
    private final OutboxMarker outboxMarker;          // separate bean: markPublished runs in its own short @Transactional
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final OutboxProperties props;             // @ConfigurationProperties record: batch size, send timeout

    @Scheduled(fixedDelayString = "${outbox.relay.delay:PT0.2S}")     // property-driven, never a literal
    @SchedulerLock(name = "outbox-relay", lockAtMostFor = "PT1M")      // ShedLock: ONE active relay keeps per-aggregate order (§6)
    public void publishPending() {
        try {
            for (OutboxEntity row : outboxRepo.findByPublishedAtIsNullOrderByCreatedAtAsc(Limit.of(props.batchSize()))) {   // no DB transaction / row locks held here
                // topic from the aggregate type (a constant map, never a literal per row); key = aggregate id (§6)
                var record = new ProducerRecord<>(topicFor(row.getAggregateType()), row.getAggregateId(), row.getPayload());
                record.headers().add("event-id", row.getId().toString().getBytes(StandardCharsets.UTF_8));
                if (row.getTraceparent() != null) {
                    record.headers().add("traceparent", row.getTraceparent().getBytes(StandardCharsets.UTF_8));
                }
                kafkaTemplate.send(record).get(props.sendTimeout().toMillis(), TimeUnit.MILLISECONDS);  // bounded wait for the broker ack
                outboxMarker.markPublished(row.getId());   // short transaction, after the ack
            }
        } catch (Exception e) {                        // a scheduled job never throws (spring-boot-conventions §7b)
            log.warn("Outbox relay stopped at the first failed row; it retries on the next tick", e);
        }
    }
}

public interface OutboxRepository extends JpaRepository<OutboxEntity, UUID> {
    List<OutboxEntity> findByPublishedAtIsNullOrderByCreatedAtAsc(Limit limit);   // Limit: Spring Data 3.2+
}
```

Stopping at the first failed row keeps per-aggregate order. **One active
relay** (ShedLock, as for every `@Scheduled` job) is the default. Several
concurrent relays with `SELECT … FOR UPDATE SKIP LOCKED` scale further but
break per-aggregate ordering unless each relay locks whole aggregates
(e.g. `pg_try_advisory_xact_lock(hashtext(aggregate_id))`) ordered by
`created_at`; if you go that way, send asynchronously, join every send with a
timeout, and keep the locking transaction short — never hold row locks across
one synchronous broker round-trip per row (`persistence` §4).

- A dedicated `outbox` table in the same DB as the entity.
- A `@Scheduled` (or **Debezium CDC** for high throughput) relay polls
  unpublished rows (`publishedAt IS NULL`) and publishes them, setting `publishedAt` only after the broker has acknowledged the send.
- Every record carries an **`event-id` header** = the outbox row id (UUID);
  consumers dedupe on it (§4).
- The relay is **idempotent**: if the broker accepts the event but the
  mark-as-sent fails, the next tick re-publishes it. Consumers must handle
  this (see below).

### Outbox Performance & Clean-up

For high-throughput services, the outbox table can grow rapidly:
1. **Indexes**: Ensure `publishedAt` (a partial index on the unpublished rows works well) and `createdAt` are indexed — the `outbox-migration.sql.tmpl` template ships both.
2. **Partitioning**: Consider Postgres table partitioning by `createdAt` (e.g., one partition per day).
3. **Retention**: Run a background job to delete records published more than 7 days ago.
4. **Batching**: The relay should fetch and publish in batches of 100-500 to minimize overhead.

## 4. Consumer — idempotent + at-least-once

Brokers guarantee at-least-once. The consumer must be **idempotent**:

```java
@Component
@RequiredArgsConstructor
public class InvoiceCreatedConsumer {

    private final FooService service;

    @KafkaListener(topics = "${kafka.topics.invoices.name}", groupId = "${kafka.topics.invoices.group-id}")
    public void on(ConsumerRecord<String, InvoiceCreatedEvent> rec, Acknowledgment ack) {
        var header = rec.headers().lastHeader("event-id");
        if (header == null) {                       // not retryable: excluded in @RetryableTopic, goes straight to the DLT
            throw new IllegalArgumentException("Record without event-id header at offset " + rec.offset());
        }
        var eventId = new String(header.value(), StandardCharsets.UTF_8);
        service.handleOnce(eventId, rec.value());   // @Transactional: dedupe insert + business effect commit together
        ack.acknowledge();                          // only after the transaction committed
    }
}

@Service
@RequiredArgsConstructor
public class FooService {
    private final ProcessedEventRepository processed;

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
  effects are atomic with the dedupe record. Domain exceptions are
  **unchecked** (`exception-handling`), so a failing `handle(event)` rolls
  back the dedupe row too and the redelivery is processed again. Never catch
  and swallow inside `handleOnce`; a checked exception from a third-party
  API must be wrapped or declared in `rollbackFor`, or the event would be
  marked processed without its effect.
- Use **manual ack** + **at-least-once**; commit offset only after the
  business transaction commits.

The relay sends the payload as a JSON `String`; the consumer turns it into
the event record. Configure both sides explicitly (topic and group come from
properties, never literals):

```yaml
kafka:
  topics:
    invoices:
      name: ${KAFKA_TOPIC_INVOICES:invoices}
      group-id: ${spring.application.name}
spring:
  kafka:
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.apache.kafka.common.serialization.StringSerializer   # payload is already JSON
    consumer:
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.springframework.kafka.support.serializer.ErrorHandlingDeserializer
      properties:
        spring.deserializer.value.delegate.class: org.springframework.kafka.support.serializer.JsonDeserializer
        spring.json.value.default.type: com.example.foo.event.InvoiceCreatedEvent
        spring.json.use.type.headers: false
        spring.json.trusted.packages: com.example.foo.event
```

`ErrorHandlingDeserializer` turns a poison message into a non-retryable
error that reaches the DLT instead of looping.

## 5. Dead-letter topic

After **N retries** with exponential backoff, send to a `<topic>-dlt` (Spring Kafka's default suffix) and
emit a **metric + alert** so an operator notices. Default values (Spring Boot non-blocking retry topics, since
Boot 2.7; the `backoff.*` keys are the Boot 3.4+ names that replace the deprecated `delay` / `multiplier` /
`max-delay`):

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
        backoff:
          delay: 1s
          multiplier: 2
          max-delay: 30s
```

A DLT record carries `kafka_dlt-exception-fqcn`, `kafka_dlt-exception-message` and `kafka_dlt-original-topic` headers explaining the failure. A redrive
operator tool replays from DLT after a fix.

### 5a. Exactly-once — what it does and does not cover

- Kafka **exactly-once semantics (EOS)** only covers *read from Kafka →
  write to Kafka* inside one Kafka transaction: set
  `spring.kafka.producer.transaction-id-prefix` and
  `spring.kafka.consumer.isolation-level: read-committed`.
- It does **not** cover a database write or an HTTP call. For those,
  "exactly-once effect" = at-least-once delivery + the idempotent consumer
  (§4) + the outbox (§3). That is the default for every service here.

## 6. Concurrency & ordering

- **Partition key = aggregate id.** Guarantees in-order processing per
  aggregate; allows parallelism across aggregates.
- Consumer concurrency ≤ partition count.
- **Never** assume cross-partition ordering. If you need it, redesign.

## 7. Testing

- **Unit tests** use a pure Mockito mock of the producer interface — no
  broker. (`EmbeddedKafkaBroker` is a broker: `integration-tests` forbids
  embedded brokers, so broker behaviour is tested only with Testcontainers.)
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
bound the call with a short timeout + circuit breaker (`resilience-patterns`) and let failures flow to the
retry topics (§5), or hand off to a `@Async` executor with backpressure — but only if the ack waits for the
async work to commit. Acking from another thread needs `ack-mode: manual` **and**
`ContainerProperties.setAsyncAcks(true)`: acks then arrive out of order, the container commits an offset only
once every earlier record is acked, and it pauses the partition while acks are pending. If that is more
than you need, don't hand off. Never ack early: an ack before the work commits loses the message on a crash and breaks
§4's at-least-once.
❌ Never use messaging for request/response. Use HTTP or gRPC.

## 8. Templates

- [`KafkaConfig.java.tmpl`](./templates/KafkaConfig.java.tmpl) — Baseline Kafka producer/consumer configuration.
- [`IdempotentConsumer.java.tmpl`](./templates/IdempotentConsumer.java.tmpl) — Pattern for deduplicating incoming events.
- [`OutboxEntity.java.tmpl`](./templates/OutboxEntity.java.tmpl) — Database entity for the Transactional Outbox.
- [`outbox-migration.sql.tmpl`](./templates/outbox-migration.sql.tmpl) — Flyway migration for the outbox and processed-events tables (save as the next `V<n>__create_outbox.sql`).
- [`DlqHandler.java.tmpl`](./templates/DlqHandler.java.tmpl) — Standard Dead Letter Queue processing.

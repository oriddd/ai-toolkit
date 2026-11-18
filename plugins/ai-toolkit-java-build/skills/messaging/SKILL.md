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
version: 1.2
last_reviewed: 2026-11-15
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
├── handler/             # event-driven service: orchestrators the consumers call
└── operation/           # REST service: use-case orchestrators (publish events as side-effects)
```

The `code-structure` ArchUnit test layers `..messaging.consumer..` and `..messaging.producer..` as separate slices.

## Dependencies

```xml
<dependency><groupId>org.springframework.kafka</groupId><artifactId>spring-kafka</artifactId></dependency>   <!-- version from the Boot BOM -->
<dependency><groupId>net.javacrumbs.shedlock</groupId><artifactId>shedlock-spring</artifactId><version>6.10.0</version></dependency>   <!-- OutboxRelay -->
<dependency><groupId>net.javacrumbs.shedlock</groupId><artifactId>shedlock-provider-jdbc-template</artifactId><version>6.10.0</version></dependency>
<dependency><groupId>io.micrometer</groupId><artifactId>micrometer-tracing-bridge-otel</artifactId></dependency>   <!-- OutboxWriter: Tracer + Propagator -->
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-amqp</artifactId></dependency>   <!-- RabbitMQ instead of Kafka -->
```

`OutboxWriter` needs `micrometer-tracing` (apply the `observability` step first) and `OutboxRelay` both ShedLock artifacts
(`ShedLockConfig`, `shedlock-migration.sql`); neither compiles without them. The templates also need the `persistence` dependencies (outbox entity, `TransactionTemplate`). Boot 4 names the Kafka starter `spring-boot-starter-kafka`
(`spring-boot-conventions` `references/spring-boot-4.md`).

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

Avro + Schema Registry, Protobuf or JSON Schema; always forward + backward compatible, shipped as a versioned artifact.
Table and rules: [`references/schema-management.md`](./references/schema-management.md).

## 3. Producer — transactional outbox

The naïve pattern "save row + publish event" is **wrong** — the publish can
succeed and the DB commit fail, or vice-versa.

Canonical pattern: row and outbox entry in one DB transaction; an async relay publishes.

Implementation:

```java
@Service
public class InvoiceService {
    @Transactional(rollbackFor = Exception.class)
    public Invoice create(CreateRequest req) throws BaseDomainException {
        var invoice = new Invoice(req.id(), req.name());
        invoiceRepo.save(invoice);
        outbox.append("invoice", invoice.getId(), new InvoiceCreatedEvent(invoice.getId(), invoice.getName(), now()));  // OutboxWriter: MANDATORY tx, stores the traceparent
        return invoice;
    }
}
```

The relay is `OutboxRelay.java.tmpl`: a `@Scheduled` + `@SchedulerLock` poll of `findByPublishedAtIsNullOrderByCreatedAtAsc(Limit.of(batch))`
(no transaction or row lock held), one `ProducerRecord` per row (topic from `outbox.relay.topics.<aggregateType>`, key =
aggregate id, `event-id` and `traceparent` headers), a bounded `send(...).get(timeout)` for the broker ack, then
`OutboxMarker.markPublished(id)` in its own short `@Transactional` (a separate bean so the call goes through the proxy).
It catches everything: a scheduled job never throws (`spring-boot-conventions` §7b). Companion templates:
`OutboxWriter` (the `append` above), `OutboxRepository`, `OutboxProperties`. The writer, relay, marker and `IdempotentConsumer`
need the database and the broker, so they carry `@Profile("!component-test")` (`component-tests` §3b): a service that calls
`OutboxWriter` gets a `@MockitoBean` of it in its component test.

Stopping at the first failed row keeps per-aggregate order. **One active
relay** (ShedLock, as for every `@Scheduled` job — setup in `references/delivery-and-testing.md`) is the default (lease rule there). Several
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

## 4. Consumer — idempotent + at-least-once

Brokers guarantee at-least-once. The consumer must be **idempotent**:

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class InvoiceCreatedConsumer {

    private final FooService service;
    private final ObjectMapper objectMapper;

    @RetryableTopic(                                 // §5: retries, backoff, DLT and the non-retryable exceptions
            attempts = "${kafka.retry.attempts:5}",
            backoff = @Backoff(delayExpression = "${kafka.retry.delay-ms:1000}",
                    multiplierExpression = "${kafka.retry.multiplier:2}",
                    maxDelayExpression = "${kafka.retry.max-delay-ms:30000}"),
            exclude = {IllegalArgumentException.class, JsonProcessingException.class},
            topicSuffixingStrategy = TopicSuffixingStrategy.SUFFIX_WITH_INDEX_VALUE)
    @KafkaListener(topics = "${kafka.topics.invoices.name}", groupId = "${kafka.topics.invoices.group-id}")
    public void on(ConsumerRecord<String, String> rec, Acknowledgment ack) throws Exception {
        var header = rec.headers().lastHeader("event-id");
        if (header == null) {                       // not retryable: excluded above, goes straight to the DLT
            throw new IllegalArgumentException("Record without event-id header at offset " + rec.offset());
        }
        var eventId = new String(header.value(), StandardCharsets.UTF_8);
        var event = objectMapper.readValue(rec.value(), InvoiceCreatedEvent.class);   // poison JSON: excluded, straight to the DLT
        service.handleOnce(eventId, event);         // @Transactional: dedupe insert + business effect commit together
        ack.acknowledge();                          // only after the transaction committed
    }

    @DltHandler
    public void onDlt(String payload, @Header(KafkaHeaders.ORIGINAL_TOPIC) String originalTopic) {
        // log + count (metric + alert, §5); never throw — the DLT is the terminal queue
    }
}

@Service
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class FooService {
    private final ProcessedEventRepository processed;

    @Transactional(rollbackFor = Exception.class)
    public void handleOnce(String eventId, InvoiceCreatedEvent event) throws BaseDomainException {
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
  **checked** (`exception-handling`): `rollbackFor = Exception.class` rolls the dedupe row back with a failing
  `handle(event)`; a `TransactionTemplate` needs `status.setRollbackOnly()` and a
  rethrow after `execute` (`IdempotentConsumer.java.tmpl`). Never swallow a failure in `handleOnce`.
- Use **manual ack** + **at-least-once**; commit offset only after the
  business transaction commits.

The relay sends the payload as a JSON `String`, and the consumer reads it as a
`String` and maps it with the `ObjectMapper` (above). Keep the value a `String`
on **both** sides: the dead-letter recoverer republishes the consumed value
through the same `StringSerializer` `KafkaTemplate`, so a consumer that
deserializes to the event record (`JsonDeserializer`) makes every DLT/retry
publish fail with `SerializationException` — the record is redelivered forever,
the partition is blocked and nothing reaches the DLT. Configure both sides
explicitly (topic and group come from properties, never literals). Merge under the existing top-level keys of
`application.yaml` (one `spring:` block, with the §5 listener keys):

```yaml
kafka:
  topics:
    invoices:
      name: ${KAFKA_TOPIC_INVOICES:invoices}
      group-id: ${spring.application.name}
  retry:                       # read by @RetryableTopic (§5)
    attempts: 5
    delay-ms: 1000
    multiplier: 2
    max-delay-ms: 30000
spring:
  kafka:
    producer:
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.apache.kafka.common.serialization.StringSerializer   # payload is already JSON
    consumer:
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.apache.kafka.common.serialization.StringDeserializer  # mapped with ObjectMapper in the listener
```

A poison message (unparseable JSON, missing `event-id`) is a **non-retryable**
error: the listener throws an excluded exception and the record goes straight
to the DLT instead of looping or burning the retry topics.

## 5. Dead-letter topic

After **N retries** with exponential backoff, send to a `<topic>-dlt` (Spring Kafka's default suffix) and
emit a **metric + alert** so an operator notices. Default values: 5 attempts, 1s initial delay, multiplier 2,
max delay 30s — the `kafka.retry.*` keys of §4, applied by `@RetryableTopic` on the listener (non-blocking retry
topics `<topic>-retry-0..n`, then `<topic>-dlt`; the `DlqHandler` template is the same recipe). Merge `listener` under the
`spring.kafka` block of §4:

```yaml
spring:
  kafka:
    listener:
      ack-mode: manual
      concurrency: 3
      missing-topics-fatal: false
```

Use the annotation, not Boot's `spring.kafka.retry.topic.*` properties (§5b: they cannot exclude exceptions and do
not create the topics). **Non-blocking retry topics break per-key order**: a failed record moves to `-retry-0` while
later records of the same aggregate are processed. An order-sensitive consumer uses blocking retries instead
(`DefaultErrorHandler` + `DeadLetterPublishingRecoverer`, §5b). DLT header names differ by path (§5b). A redrive
operator tool replays from DLT after a fix.

## 6. Concurrency & ordering

- **Partition key = aggregate id.** Guarantees in-order processing per
  aggregate; allows parallelism across aggregates.
- Consumer concurrency ≤ partition count.
- **Never** assume cross-partition ordering. If you need it, redesign.

## Reference map — load only the part you are working on

Sections below keep their names and numbers but live in `references/` so this file stays small.

| Sections | Topic | Load when | File |
| --- | --- | --- | --- |
| RabbitMQ | confirms, `messageId`, DLX/DLQ, listener retry | the broker is RabbitMQ | [`rabbitmq.md`](./references/rabbitmq.md) |
| §2 | schema formats and compatibility rules | choosing or evolving the event schema | [`schema-management.md`](./references/schema-management.md) |
| §3 Outbox Performance & Clean-up, §5a, §5b, §7 | outbox indexes / partitioning / retention, exactly-once scope, retry topology and DLT headers, testing | tuning the outbox, choosing blocking vs non-blocking retries, considering Kafka transactions, writing messaging tests | [`delivery-and-testing.md`](./references/delivery-and-testing.md) |

## Do / Don't

✅ Events are records; producer uses transactional outbox; consumer is
idempotent; partition key = aggregate id; DLT after N retries.
✅ Schemas are versioned and compatibility-checked in CI.
❌ Never publish from inside an HTTP handler without going through the outbox
("save then publish" race).
❌ Never block a consumer thread on a sync HTTP call to a slow downstream —
bound the call with a short timeout + circuit breaker (`resilience-patterns`) and let failures flow to the
retry topics (§5), or hand off to a `@Async` executor with backpressure — but ack only after the async work commits
(`ack-mode: manual` plus `ContainerProperties.setAsyncAcks(true)`: the container commits an offset once every earlier record is
acked). Never ack early: it loses the message on a crash and breaks §4's at-least-once.
❌ Never use messaging for request/response. Use HTTP or gRPC.

## 8. Templates

Copy each class with its `*Test.java.tmpl` (Jacoco per class and PIT apply, `unit-tests`); `KafkaConfig` and `ShedLockConfig` are wiring-only.

- [`KafkaConfig.java.tmpl`](./templates/KafkaConfig.java.tmpl) — Baseline Kafka producer/consumer configuration.
- [`IdempotentConsumer.java.tmpl`](./templates/IdempotentConsumer.java.tmpl) — Pattern for deduplicating incoming events.
- [`OutboxEntity.java.tmpl`](./templates/OutboxEntity.java.tmpl) — Database entity for the Transactional Outbox.
- [`OutboxWriter`](./templates/OutboxWriter.java.tmpl), [`OutboxRelay`](./templates/OutboxRelay.java.tmpl), [`OutboxMarker`](./templates/OutboxMarker.java.tmpl), [`OutboxRepository`](./templates/OutboxRepository.java.tmpl), [`OutboxProperties`](./templates/OutboxProperties.java.tmpl) — writer, relay and its support classes.
- [`ShedLockConfig.java.tmpl`](./templates/ShedLockConfig.java.tmpl), [`shedlock-migration.sql.tmpl`](./templates/shedlock-migration.sql.tmpl) — one active relay per cluster.
- [`outbox-migration.sql.tmpl`](./templates/outbox-migration.sql.tmpl) — Flyway migration for the outbox and processed-events tables (save as the next `V<n>__create_outbox.sql`).
- [`DlqHandler.java.tmpl`](./templates/DlqHandler.java.tmpl) — Standard Dead Letter Queue processing.
- Tests: [`OutboxWriterTest`](./templates/OutboxWriterTest.java.tmpl), [`OutboxRelayTest`](./templates/OutboxRelayTest.java.tmpl), [`OutboxMarkerTest`](./templates/OutboxMarkerTest.java.tmpl), [`IdempotentConsumerTest`](./templates/IdempotentConsumerTest.java.tmpl), [`DlqHandlerTest`](./templates/DlqHandlerTest.java.tmpl).

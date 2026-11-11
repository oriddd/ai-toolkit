# Messaging Skill — Outbox operations, exactly-once scope, testing

Part of the [`messaging`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

### Outbox Performance & Clean-up

For high-throughput services, the outbox table can grow rapidly:
1. **Indexes**: Ensure `publishedAt` (a partial index on the unpublished rows works well) and `createdAt` are indexed — the `outbox-migration.sql.tmpl` template ships both.
2. **Partitioning**: Consider Postgres table partitioning by `createdAt` (e.g., one partition per day).
3. **Retention**: Run a background job to delete records published more than 7 days ago.
4. **Batching**: The relay should fetch and publish in batches of 100-500 to minimize overhead.

### 5a. Exactly-once — what it does and does not cover

- Kafka **exactly-once semantics (EOS)** only covers *read from Kafka →
  write to Kafka* inside one Kafka transaction: set
  `spring.kafka.producer.transaction-id-prefix` and
  `spring.kafka.consumer.isolation-level: read-committed`.
- It does **not** cover a database write or an HTTP call. For those,
  "exactly-once effect" = at-least-once delivery + the idempotent consumer
  (§4) + the outbox (§3). That is the default for every service here.

## 7. Testing

- **Unit tests** use a pure Mockito mock of the producer interface — no
  broker. (`EmbeddedKafkaBroker` is a broker: `integration-tests` forbids
  embedded brokers, so broker behaviour is tested only with Testcontainers.)
- **Integration tests** use a **Testcontainer** (`KafkaContainer` /
  `RabbitMQContainer`) — see `integration-tests`.
- The outbox relay is unit-tested with a fake clock; the at-least-once
  consumer is integration-tested by publishing the same event twice and
  asserting one effect.

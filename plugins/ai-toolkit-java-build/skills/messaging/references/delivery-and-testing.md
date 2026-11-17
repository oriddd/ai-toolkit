# Messaging Skill — Outbox operations, exactly-once scope, testing

Part of the [`messaging`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

### Outbox Performance & Clean-up

For high-throughput services, the outbox table can grow rapidly:
1. **Indexes**: Ensure `publishedAt` (a partial index on the unpublished rows works well) and `createdAt` are indexed — the `outbox-migration.sql.tmpl` template ships both.
2. **Partitioning**: Consider Postgres table partitioning by `createdAt` (e.g., one partition per day).
3. **Retention**: Run a background job to delete records published more than 7 days ago. Prune `processed_events`
   too, but only rows older than the longest possible redelivery (topic retention + DLT redrive window) — a dedupe
   row deleted sooner lets a late redelivery run its effect twice.
4. **Batching**: The relay should fetch and publish in batches of 100-500 to minimize overhead.

### 5a. Exactly-once — what it does and does not cover

- Kafka **exactly-once semantics (EOS)** only covers *read from Kafka →
  write to Kafka* inside one Kafka transaction: set
  `spring.kafka.producer.transaction-id-prefix` and
  `spring.kafka.consumer.isolation-level: read-committed`.
- It does **not** cover a database write or an HTTP call. For those,
  "exactly-once effect" = at-least-once delivery + the idempotent consumer
  (§4) + the outbox (§3). That is the default for every service here.

### 5b. Retry topology and DLT headers

**Non-blocking (`@RetryableTopic`, the §5 default).** Prefer the annotation over Boot's `spring.kafka.retry.topic.*`
properties: those cannot list non-retryable exceptions (a missing header would be retried N times) and Boot builds
them with `doNotAutoCreateRetryTopics()`, so on a cluster without broker-side auto-creation the retry and DLT topics
do not exist. `@RetryableTopic` creates them (`autoCreateTopics`, default `true`); where the platform forbids that,
create the retry topics (`<topic>-retry-0`, `-1`, … one per retry) and `<topic>-dlt` together with the topic itself.
With a constant delay (multiplier 1) Spring Kafka reuses a single `<topic>-retry` topic instead of `-retry-0..n`; the indexed names appear with an exponential back-off (verified against Confluent and Apache Kafka images). The partition keeps moving while a record waits in a retry topic, so **per-key ordering is lost** for retried records.

**Blocking (order-sensitive consumers).** When events of one aggregate must be applied in order, retry in place and
dead-letter at the end — the partition waits, order holds:

```java
@Bean
DefaultErrorHandler kafkaErrorHandler(KafkaTemplate<String, String> template, KafkaRetryProperties retry) {
    var backOff = new ExponentialBackOffWithMaxRetries(retry.attempts() - 1);
    backOff.setInitialInterval(retry.delayMs());
    backOff.setMultiplier(retry.multiplier());
    backOff.setMaxInterval(retry.maxDelayMs());
    var handler = new DefaultErrorHandler(new DeadLetterPublishingRecoverer(template), backOff);   // → <topic>-dlt
    handler.addNotRetryableExceptions(IllegalArgumentException.class, JsonProcessingException.class);
    return handler;
}
```

`KafkaRetryProperties` is the `@ConfigurationProperties(prefix = "kafka.retry")` record of the §4 keys
(`attempts`, `delayMs`, `multiplier`, `maxDelayMs`). Boot applies a single `CommonErrorHandler` bean to its listener container factory. Keep the total back-off below
`max.poll.interval.ms`, or the consumer is evicted from the group mid-retry. Do not combine it with
`@RetryableTopic` on the same listener.

**DLT headers.** The `@RetryableTopic` path writes `kafka_exception-fqcn`, `kafka_exception-message` and
`kafka_original-topic` (`KafkaHeaders.EXCEPTION_FQCN`, `EXCEPTION_MESSAGE`, `ORIGINAL_TOPIC`). A plain
`DeadLetterPublishingRecoverer` (the blocking path) keeps its defaults, `kafka_dlt-exception-fqcn`,
`kafka_dlt-exception-message`, `kafka_dlt-original-topic` (`KafkaHeaders.DLT_*`). A redrive tool reads the names of
the path it serves.

### ShedLock for the relay (and every `@Scheduled` job)

```xml
<dependency><groupId>net.javacrumbs.shedlock</groupId><artifactId>shedlock-spring</artifactId><version>6.10.0</version></dependency>
<dependency><groupId>net.javacrumbs.shedlock</groupId><artifactId>shedlock-provider-jdbc-template</artifactId><version>6.10.0</version></dependency>
```

```java
@Configuration
@EnableScheduling
@EnableSchedulerLock(defaultLockAtMostFor = "PT1M")
@Profile("!component-test")                                  // component tests have no DataSource (component-tests §3b)
class ShedLockConfig {
    @Bean
    LockProvider lockProvider(DataSource dataSource) {
        return new JdbcTemplateLockProvider(JdbcTemplateLockProvider.Configuration.builder()
                .withJdbcTemplate(new JdbcTemplate(dataSource))
                .usingDbTime()                               // one clock for every pod
                .build());
    }
}
```

```sql
-- V00x__create_shedlock.sql
CREATE TABLE shedlock (
    name       VARCHAR(64)  NOT NULL PRIMARY KEY,
    lock_until TIMESTAMP    NOT NULL,
    locked_at  TIMESTAMP    NOT NULL,
    locked_by  VARCHAR(255) NOT NULL
);
```

6.10.0 is the release verified on Spring Boot 3.5; check the ShedLock release notes before moving to 7.x.

## 7. Testing

- **Unit tests** use a pure Mockito mock of the producer interface — no
  broker. (`EmbeddedKafkaBroker` is a broker: `integration-tests` forbids
  embedded brokers, so broker behaviour is tested only with Testcontainers.)
- **Integration tests** use a **Testcontainer** (`KafkaContainer` /
  `RabbitMQContainer`) — see `integration-tests`.
- Verified recipe (Postgres + Kafka containers, `@SpringBootTest`, `@ServiceConnection` on both, short `kafka.retry.*`
  overrides): outbox row → relay → record with the `event-id` header → consumer effect, row marked published, ShedLock row
  created; the same `event-id` twice → one effect; missing header or invalid JSON → `<topic>-dlt` without retries; a failing
  effect → retry topics, then DLT, and no `processed_events` row left behind.
- Verified outbox run (Postgres 16 + `apache/kafka:3.9.1`, two application contexts on one database): a checked
  exception after `append` rolls the entity row and the outbox row back together; `append` outside a transaction is
  refused (`MANDATORY`); rows written by a context that is then shut down are published, in order, by the next
  context (restart); a failure between the broker ack and `markPublished` publishes the row again on the next tick (6
  records for 4 events) and the consumer's `processed_events` gate keeps the effect at 4; a paused broker leaves the
  row unpublished (the relay logs and stops) and `unpause` publishes it; the record carries `event-id`, the aggregate
  id as key and `traceparent`; the `shedlock` row exists.
- The outbox relay is unit-tested with a fake clock; the at-least-once
  consumer is integration-tested by publishing the same event twice and
  asserting one effect.

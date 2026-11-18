# Messaging Skill — RabbitMQ variant

Part of the [`messaging`](../SKILL.md) skill. The outbox table, `OutboxWriter`, `OutboxMarker` and the idempotent-consumer
rule are broker-neutral (SKILL.md §3, §4). Only the publish step of the relay and the consumer change. Dependency:
`spring-boot-starter-amqp`.

```yaml
spring:
  rabbitmq:
    publisher-confirm-type: correlated      # the broker acks every publish
    publisher-returns: true
    template.mandatory: true                # an unroutable message comes back instead of vanishing
    listener.simple:
      default-requeue-rejected: false       # a failed message is dead-lettered, never requeued in a loop
      retry: { enabled: true, max-attempts: 3, initial-interval: 100ms }
```

Topology: the work queue declares a dead-letter exchange, so a message that exhausts the listener retries lands in
`<queue>.dlq`:

```java
@Bean Queue invoices() { return QueueBuilder.durable("invoices").deadLetterExchange("events.dlx").deadLetterRoutingKey("invoices.dlq").build(); }
@Bean Queue invoicesDlq() { return QueueBuilder.durable("invoices.dlq").build(); }
```

Publish step of the relay: the outbox row id is the AMQP `messageId` (the equivalent of Kafka's `event-id`), the publish
waits for the confirm, and a negative confirm, a timeout or a returned message is a failure — the relay stops there and
leaves the row unpublished:

```java
Message message = MessageBuilder.withBody(json.getBytes(UTF_8))
        .setContentType(MessageProperties.CONTENT_TYPE_JSON)
        .setMessageId(eventId.toString())
        .setDeliveryMode(MessageDeliveryMode.PERSISTENT)
        .build();
CorrelationData correlation = new CorrelationData(eventId.toString());
template.send(exchange, routingKey, message, correlation);
CorrelationData.Confirm confirm = correlation.getFuture().get(timeout.toMillis(), TimeUnit.MILLISECONDS);
if (!confirm.isAck())                  { throw ExceptionMessages.dependencyUnavailable("rabbitmq", null); }
if (correlation.getReturned() != null) { throw ExceptionMessages.dependencyCallFailed("rabbitmq", 312); }   // unroutable
```

Wrap `TimeoutException`, `ExecutionException` and `AmqpException` into `UnavailableException`. Consumer:
`@RabbitListener(queues = "invoices")` reads `message.getMessageProperties().getMessageId()` and runs the same
`processed_events` insert-then-effect transaction as `IdempotentConsumer`; a missing id throws
`AmqpRejectAndDontRequeueException` (straight to the DLQ). Listener acks automatically when the method returns, after
the transaction committed.

Verified against `rabbitmq:4-management-alpine` (Testcontainers, Spring Boot 3.5): the same `messageId` published twice →
one effect; a failing message is attempted 3 times, then arrives in `invoices.dlq`; an unroutable key →
`DependencyException`; a missing exchange → `UnavailableException`.

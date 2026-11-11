---
name: python-messaging
description: >
  Python async messaging — transactional outbox written in the use case's unit of work, a relay with FOR UPDATE
  SKIP LOCKED, an idempotent consumer keyed by event id, bounded retries and a dead-letter topic (aiokafka). Use when
  a Python service publishes or consumes domain events.
tier: should
applies_to: [rest, worker]
depends_on: [python-code-structure, python-persistence, python-error-handling]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-11
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# Python Messaging Skill
## When to use
When a service must tell others that something happened (publish a domain event) or must react to another
service's events (consume), with PostgreSQL as its database. Delivery is **at least once**: the producer may
publish twice, so every consumer is idempotent.

## Layout

```
src/my_service/
├── models/events.py                 # DomainEvent base + OrderPlaced (frozen pydantic, versioned topic)
├── repositories/
│   ├── orm.py                       # + OutboxRow, ProcessedMessageRow
│   ├── outbox.py                    # Outbox Protocol + SqlOutbox(session)
│   └── unit_of_work.py              # UnitOfWork gains `outbox: Outbox`
└── messaging/
    ├── publisher.py                 # EventPublisher Protocol
    ├── kafka_publisher.py           # aiokafka adapter (idempotent producer, acks=all)
    ├── outbox_relay.py              # OutboxRelay.publish_batch + run_relay loop
    ├── idempotent_consumer.py       # claim-then-handle in one transaction
    └── consumer_loop.py             # poll, retry, dead-letter, commit offsets
```

`messaging/` is an adapter layer like `repositories/` and `clients/`: it may import repositories and models,
never `api/` or `services/`.

## Dependencies
```toml
dependencies = ["aiokafka>=0.11", "sqlalchemy[asyncio]>=2.0.30", "asyncpg>=0.29"]
```
aiokafka ships no type information: add a narrow `[[tool.mypy.overrides]]` with `module = ["aiokafka", "aiokafka.*"]`
and `ignore_missing_imports = true` (`python-static-analysis` §2), and keep it behind the Protocols below.

## 1. Events are immutable, versioned contracts
```python
class DomainEvent(BaseModel):
    model_config = ConfigDict(frozen=True)
    topic: ClassVar[str]
    event_id: UUID                   # unique per event: the consumer's idempotency key
    occurred_at: datetime            # from the injected Clock, timezone-aware

    def key(self) -> str:            # partition key: events of one aggregate stay ordered
        raise NotImplementedError

class OrderPlaced(DomainEvent):
    topic: ClassVar[str] = "orders.order-placed.v1"
    order_id: UUID
    customer_id: str
    total_cents: int

    def key(self) -> str:
        return str(self.order_id)
```
Carry identifiers and the facts consumers need, not whole aggregates or personal data. Changes are additive;
a breaking change is a new topic version (`.v2`) published alongside the old one until consumers move.

## 2. Producer: transactional outbox, never publish inside the use case
Writing the order and calling Kafka are two systems: either can fail after the other succeeded. The use case
therefore writes the event to an `outbox` table **in the same unit of work** as the state change:

```python
async with self._uow_factory() as uow:
    await uow.orders.add(order)
    uow.outbox.add(OrderPlaced(event_id=self._ids.new_id(), occurred_at=self._clock.now(),
                               order_id=order.id, customer_id=order.customer_id,
                               total_cents=order.total_cents))
    await uow.commit()               # order and event commit together, or neither does
```

```python
class OutboxRow(Base):
    __tablename__ = "outbox"
    id: Mapped[UUID] = mapped_column(primary_key=True)           # = event_id
    topic: Mapped[str] = mapped_column(String(128))
    key: Mapped[str] = mapped_column(String(128))
    event_type: Mapped[str] = mapped_column(String(64))
    payload: Mapped[dict[str, object]] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    __table_args__ = (
        Index("ix_outbox_unpublished", "created_at", postgresql_where=text("published_at IS NULL")),
    )
```
`SqlOutbox.add` stores `event.model_dump(mode="json")`. Unit tests use an `InMemoryOutbox` fake on the
in-memory unit of work and assert the exact event (`python-unit-tests` §3).

## 3. The relay: lock, publish, mark
```python
async def publish_batch(self) -> int:
    async with self._factory() as session, session.begin():
        rows = (await session.scalars(
            select(OutboxRow).where(OutboxRow.published_at.is_(None))
            .order_by(OutboxRow.created_at, OutboxRow.id).limit(self._batch_size)
            .with_for_update(skip_locked=True)         # two relay replicas never take the same rows
        )).all()
        for row in rows:
            await self._publisher.publish(row.topic, row.key, json.dumps(row.payload).encode(),
                                          {"event_id": str(row.id), "event_type": row.event_type})
        if rows:
            await session.execute(update(OutboxRow).where(OutboxRow.id.in_([r.id for r in rows]))
                                  .values(published_at=func.now()))
    return len(rows)
```
- A publish failure rolls the transaction back and the rows stay unpublished; the next batch retries them.
  A crash after publishing but before commit publishes again: that is the at-least-once contract.
- `run_relay(relay, stop, idle_seconds)` loops until a `stop` event is set, logs failures with
  `logger.exception` and keeps going, and sleeps only when a batch was empty. Run it as a lifespan task or a
  separate worker process; set `stop` on shutdown and await the task so an in-flight batch finishes.
- The producer is idempotent and waits for all replicas:
  `AIOKafkaProducer(bootstrap_servers=..., enable_idempotence=True, acks="all")`, started and stopped in the
  lifespan; publish with `send_and_wait` so the relay marks only what the broker acknowledged.
- Delete published rows on a schedule (`published_at < now() - interval '7 days'`); the table is not an archive.

## 4. Consumer: idempotent by event id
```python
class IdempotentConsumer:
    async def handle(self, message_id: UUID, value: bytes) -> bool:
        async with self._factory() as session, session.begin():
            claimed = await session.scalar(
                insert(ProcessedMessageRow)                 # sqlalchemy.dialects.postgresql.insert
                .values(consumer=self._name, message_id=message_id)
                .on_conflict_do_nothing()
                .returning(ProcessedMessageRow.message_id)
            )
            if claimed is None:
                return False                                # duplicate: already handled
            await self._handler(session, value)             # same transaction as the claim
        return True
```
`ProcessedMessageRow` has the primary key `(consumer, message_id)`. Claim and side effects commit together:
if the handler raises, the claim rolls back too and a redelivery is processed again. A handler that calls an
external API cannot be rolled back, so that API must be idempotent itself (pass the event id as its idempotency key).

## 5. Consumer loop: bounded retries, dead letter, then commit
```python
async def run(self) -> None:
    async for record in self._source:                       # AIOKafkaConsumer(enable_auto_commit=False)
        await self._process(record)                         # retries max_attempts, then dead-letters
        await self._source.commit()                         # commit the offset only after the outcome is durable
```
- Read `event_id` from the record headers; a missing or malformed id goes straight to the dead-letter topic.
- Retry a failing handler a few times in-process, then publish the original value and headers plus `dlt_reason`
  to `<topic>.dlt` and move on: one poison message must not block the partition.
- `enable_auto_commit=False`; offsets are committed after processing or dead-lettering, never before.
- Bind `event_id` into structlog contextvars per record (`python-observability` §2).
- The loop depends on Protocols (`CommittingSource`, `MessageHandler`, `EventPublisher`), so it is unit-tested
  with fakes: success, retry-then-success, always-failing (dead-lettered and committed), missing id.

## 6. Testing
- Unit: the use case writes the expected event to `InMemoryOutbox`; the consumer loop with fakes.
- Integration (real PostgreSQL, `python-integration-tests`): the event commits with the state change and
  disappears with a rollback; `publish_batch` publishes once and marks the row; a failing publisher leaves it
  unpublished; a second relay skips locked rows while the first is publishing; a duplicate message is handled
  once; a failing handler leaves the message claimable again. The broker itself is tested with the Kafka
  testcontainers module or left to a contract test; the relay never needs it.

## Do / Don't
- ✅ Outbox row in the same unit of work as the state change; the relay publishes later.
- ✅ Event id = outbox id = consumer idempotency key; partition key = aggregate id.
- ✅ `FOR UPDATE SKIP LOCKED` in the relay; idempotent producer with `acks="all"`.
- ✅ Manual offset commits after processing; bounded retries; a dead-letter topic.
- ❌ `await producer.send(...)` inside the use case or before `commit()`.
- ❌ Consumers that assume exactly-once delivery, or deduplicate in memory.
- ❌ Auto-commit of offsets; infinite in-process retries on one record.
- ❌ ORM rows, `datetime.now()` or personal data in event payloads.

## Cross-references
- [`python-persistence`](../python-persistence/SKILL.md) — the unit of work the outbox joins; migrations for both tables.
- [`python-error-handling`](../python-error-handling/SKILL.md) — handler errors and logging once.
- `python-integration-tests` — the real-database tests above.
- `python-observability` — correlation via `event_id`, consumer lag and dead-letter metrics.

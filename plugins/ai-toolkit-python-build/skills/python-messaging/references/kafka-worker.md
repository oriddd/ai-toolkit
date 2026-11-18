# python-messaging — consumer loop, worker and real-Kafka tests

Back to [`SKILL.md`](../SKILL.md). Every file here ran against a real `apache/kafka:3.9.1` and PostgreSQL
(testcontainers): the outbox row reached the topic through the relay, the consumer handled it once, poison
messages landed on `<topic>.dlt`, and `SIGTERM` stopped the worker process with exit code 0 and both heartbeat files.

## Events, outbox and relay

The pieces the loop and the worker import. `EventPublisher` is the port the relay and the dead-letter path share; `BatchRelay` is what `run_relay` needs, so the loop is unit-tested with a scripted relay.

### `src/my_service/models/events.py`

```python
from datetime import datetime
from typing import ClassVar
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class DomainEvent(BaseModel):
    model_config = ConfigDict(frozen=True)
    topic: ClassVar[str]
    event_id: UUID
    occurred_at: datetime

    def key(self) -> str:
        raise NotImplementedError


class OrderPlaced(DomainEvent):
    topic: ClassVar[str] = "orders.order-placed.v1"
    order_id: UUID
    customer_id: str
    total_cents: int

    def key(self) -> str:
        return str(self.order_id)
```

### `src/my_service/repositories/outbox.py`

```python
from typing import Protocol

from sqlalchemy.ext.asyncio import AsyncSession

from my_service.models.events import DomainEvent
from my_service.repositories.orm import OutboxRow


class Outbox(Protocol):
    def add(self, event: DomainEvent) -> None: ...


class SqlOutbox:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    def add(self, event: DomainEvent) -> None:
        self._session.add(
            OutboxRow(
                id=event.event_id,
                topic=event.topic,
                key=event.key(),
                event_type=type(event).__name__,
                payload=event.model_dump(mode="json"),
            )
        )
```

### `src/my_service/operations/create_order.py`

```python
from collections.abc import Callable, Sequence

from my_service.models.events import OrderPlaced
from my_service.models.order import Order
from my_service.models.requests import CreateOrderRequest
from my_service.models.responses import OrderResponse
from my_service.repositories.unit_of_work import UnitOfWork
from my_service.services.clock import Clock
from my_service.services.ids import IdGenerator
from my_service.validation.rules import Rule


class CreateOrderOperation:
    def __init__(
        self,
        uow_factory: Callable[[], UnitOfWork],
        clock: Clock,
        ids: IdGenerator,
        rules: Sequence[Rule[CreateOrderRequest]] = (),
    ) -> None:
        self._uow_factory = uow_factory
        self._clock = clock
        self._ids = ids
        self._rules = rules

    async def execute(self, body: CreateOrderRequest) -> OrderResponse:
        for rule in self._rules:
            await rule.check(body)
        order = Order(self._ids.new_id(), body.customer_id, body.total_cents, "new")
        async with self._uow_factory() as uow:
            await uow.orders.add(order)
            uow.outbox.add(
                OrderPlaced(
                    event_id=self._ids.new_id(),
                    occurred_at=self._clock.now(),
                    order_id=order.id,
                    customer_id=order.customer_id,
                    total_cents=order.total_cents,
                )
            )
            await uow.commit()
        return OrderResponse(id=order.id, status=order.status, version=order.version)
```

### `src/my_service/messaging/outbox_relay.py`

```python
import asyncio
import contextlib
import json
from collections.abc import Mapping
from typing import Protocol

import structlog
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from my_service.liveness import Heartbeat
from my_service.repositories.orm import OutboxRow

logger = structlog.get_logger()

RELAY_LOCK_KEY = 7_315_420_001


class EventPublisher(Protocol):
    async def publish(
        self, topic: str, key: str, value: bytes, headers: Mapping[str, str]
    ) -> None: ...


class BatchRelay(Protocol):
    async def publish_batch(self) -> int: ...


class OutboxRelay:
    def __init__(
        self,
        factory: async_sessionmaker[AsyncSession],
        publisher: EventPublisher,
        batch_size: int,
    ) -> None:
        self._factory = factory
        self._publisher = publisher
        self._batch_size = batch_size

    async def publish_batch(self) -> int:
        async with self._factory() as session, session.begin():
            if not await session.scalar(select(func.pg_try_advisory_xact_lock(RELAY_LOCK_KEY))):
                return 0
            rows = (
                await session.scalars(
                    select(OutboxRow)
                    .where(OutboxRow.published_at.is_(None))
                    .order_by(OutboxRow.created_at, OutboxRow.id)
                    .limit(self._batch_size)
                    .with_for_update(skip_locked=True)
                )
            ).all()
            for row in rows:
                await self._publisher.publish(
                    row.topic,
                    row.key,
                    json.dumps(row.payload).encode(),
                    {"event_id": str(row.id), "event_type": row.event_type},
                )
            if rows:
                await session.execute(
                    update(OutboxRow)
                    .where(OutboxRow.id.in_([r.id for r in rows]))
                    .values(published_at=func.now())
                )
        return len(rows)


async def run_relay(
    relay: BatchRelay, stop: asyncio.Event, idle_seconds: float, heartbeat: Heartbeat | None = None
) -> None:
    while not stop.is_set():
        if heartbeat:
            heartbeat.beat()
        try:
            published = await relay.publish_batch()
        except Exception:
            logger.exception("outbox relay batch failed")
            published = 0
        if published == 0:
            with contextlib.suppress(TimeoutError):
                await asyncio.wait_for(stop.wait(), idle_seconds)
```

### `src/my_service/messaging/kafka_publisher.py`

```python
from collections.abc import Mapping
from typing import Protocol


class Producer(Protocol):
    async def send_and_wait(
        self, topic: str, value: bytes, key: bytes, headers: list[tuple[str, bytes]]
    ) -> object: ...


class KafkaEventPublisher:
    def __init__(self, producer: Producer) -> None:
        self._producer = producer

    async def publish(self, topic: str, key: str, value: bytes, headers: Mapping[str, str]) -> None:
        await self._producer.send_and_wait(
            topic,
            value=value,
            key=key.encode(),
            headers=[(k, v.encode()) for k, v in headers.items()],
        )
```

## Consumer loop
### `src/my_service/messaging/consumer_loop.py`

```python
import asyncio
from collections.abc import Mapping, Sequence
from typing import Protocol
from uuid import UUID

import structlog

from my_service.liveness import Heartbeat
from my_service.messaging.outbox_relay import EventPublisher

logger = structlog.get_logger()


class ConsumedRecord(Protocol):
    @property
    def topic(self) -> str: ...
    @property
    def key(self) -> bytes | None: ...
    @property
    def value(self) -> bytes | None: ...
    @property
    def headers(self) -> Sequence[tuple[str, bytes]]: ...


class CommittingSource(Protocol):
    async def getmany(
        self, *, timeout_ms: int, max_records: int
    ) -> Mapping[object, Sequence[ConsumedRecord]]: ...
    async def commit(self) -> None: ...


class MessageConsumer(Protocol):
    async def handle(self, message_id: UUID, value: bytes) -> bool: ...


class ConsumerLoop:
    def __init__(
        self,
        source: CommittingSource,
        consumer: MessageConsumer,
        dead_letters: EventPublisher,
        heartbeat: Heartbeat,
        *,
        max_attempts: int = 3,
        retry_delay_seconds: float = 0.5,
    ) -> None:
        self._source = source
        self._consumer = consumer
        self._dead_letters = dead_letters
        self._heartbeat = heartbeat
        self._max_attempts = max_attempts
        self._retry_delay = retry_delay_seconds

    async def run(self, stop: asyncio.Event) -> None:
        while not stop.is_set():
            self._heartbeat.beat()
            batch = await self._source.getmany(timeout_ms=1000, max_records=1)
            for records in batch.values():
                for record in records:
                    await self._process(record)
                    await self._source.commit()

    async def _process(self, record: ConsumedRecord) -> None:
        headers = {name: value.decode() for name, value in record.headers}
        value = record.value or b""
        try:
            event_id = UUID(headers["event_id"])
        except (KeyError, ValueError) as exc:
            logger.warning("invalid event_id header", error=type(exc).__name__)
            await self._dead_letter(record, headers, value, "missing or malformed event_id")
            return
        structlog.contextvars.bind_contextvars(event_id=str(event_id))
        try:
            await self._handle_with_retries(event_id, value, record, headers)
        finally:
            structlog.contextvars.unbind_contextvars("event_id")

    async def _handle_with_retries(
        self, event_id: UUID, value: bytes, record: ConsumedRecord, headers: dict[str, str]
    ) -> None:
        for attempt in range(1, self._max_attempts + 1):
            try:
                await self._consumer.handle(event_id, value)
            except Exception as exc:  # noqa: BLE001 - any failure is retried, then dead-lettered
                logger.warning("handler failed", attempt=attempt, error=type(exc).__name__)
                if attempt == self._max_attempts:
                    await self._dead_letter(record, headers, value, type(exc).__name__)
                else:
                    await asyncio.sleep(self._retry_delay)
            else:
                return

    async def _dead_letter(
        self, record: ConsumedRecord, headers: dict[str, str], value: bytes, reason: str
    ) -> None:
        key = record.key.decode() if record.key else ""
        await self._dead_letters.publish(
            f"{record.topic}.dlt", key, value, {**headers, "dlt_reason": reason}
        )
```

`ConsumerLoop` depends on the `CommittingSource` and `MessageConsumer` Protocols, so the unit tests use fakes and the
real `AIOKafkaConsumer` satisfies the source structurally. The `# noqa: BLE001` is the one place a blind `except`
is right: any handler failure is retried, then dead-lettered, and always logged.

The parsing guard is `except (KeyError, ValueError) as exc:`. Python 3.14 allows `except KeyError, ValueError:` without
parentheses (PEP 758), but that is a `SyntaxError` on 3.12 and 3.13, and `ruff format` with `target-version = "py314"`
removes the parentheses from a clause that has no `as` name. Binding the exception (and logging its type) keeps the
parentheses, which every supported version requires.

## Idempotent consumer and example handler
### `src/my_service/messaging/idempotent_consumer.py`

```python
from typing import Protocol
from uuid import UUID

from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from my_service.repositories.orm import ProcessedMessageRow


class MessageHandler(Protocol):
    async def __call__(self, session: AsyncSession, value: bytes) -> None: ...


class IdempotentConsumer:
    def __init__(
        self, factory: async_sessionmaker[AsyncSession], name: str, handler: MessageHandler
    ) -> None:
        self._factory = factory
        self._name = name
        self._handler = handler

    async def handle(self, message_id: UUID, value: bytes) -> bool:
        async with self._factory() as session, session.begin():
            claimed = await session.scalar(
                insert(ProcessedMessageRow)
                .values(consumer=self._name, message_id=message_id)
                .on_conflict_do_nothing()
                .returning(ProcessedMessageRow.message_id)
            )
            if claimed is None:
                return False
            await self._handler(session, value)
        return True
```

### `src/my_service/messaging/handlers.py`

```python
from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession

from my_service.models.events import OrderPlaced
from my_service.repositories.orm import OrderRow


async def mark_order_received(session: AsyncSession, value: bytes) -> None:
    event = OrderPlaced.model_validate_json(value)
    await session.execute(
        update(OrderRow).where(OrderRow.id == event.order_id).values(status="received")
    )
```

## Worker process
### `src/my_service/worker.py`

```python
import asyncio
import signal
from collections.abc import AsyncIterator
from contextlib import AsyncExitStack, asynccontextmanager
from dataclasses import dataclass
from typing import Protocol

from aiokafka import AIOKafkaConsumer, AIOKafkaProducer
from prometheus_client import start_http_server
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from my_service.config.settings import AppSettings
from my_service.liveness import Heartbeat
from my_service.messaging.consumer_loop import ConsumerLoop
from my_service.messaging.handlers import mark_order_received
from my_service.messaging.idempotent_consumer import IdempotentConsumer
from my_service.messaging.kafka_publisher import KafkaEventPublisher
from my_service.messaging.outbox_relay import BatchRelay, OutboxRelay, run_relay
from my_service.observability.logging import configure_logging


class StoppableLoop(Protocol):
    async def run(self, stop: asyncio.Event) -> None: ...


@dataclass(frozen=True)
class WorkerResources:
    relay: BatchRelay
    consumer_loop: StoppableLoop


@asynccontextmanager
async def worker_resources(settings: AppSettings) -> AsyncIterator[WorkerResources]:
    async with AsyncExitStack() as stack:
        engine = create_async_engine(settings.db.sqlalchemy_url(), pool_size=settings.db.pool_size)
        stack.push_async_callback(engine.dispose)
        factory = async_sessionmaker(engine, expire_on_commit=False)
        producer = await stack.enter_async_context(
            AIOKafkaProducer(
                bootstrap_servers=settings.kafka.bootstrap_servers,
                enable_idempotence=True,
                acks="all",
            )
        )
        source = await stack.enter_async_context(
            AIOKafkaConsumer(
                *settings.kafka.topics,
                bootstrap_servers=settings.kafka.bootstrap_servers,
                group_id=settings.kafka.group_id,
                enable_auto_commit=False,
                auto_offset_reset="earliest",
            )
        )
        publisher = KafkaEventPublisher(producer)
        yield WorkerResources(
            relay=OutboxRelay(factory, publisher, batch_size=100),
            consumer_loop=ConsumerLoop(
                source,
                IdempotentConsumer(factory, settings.kafka.group_id, mark_order_received),
                publisher,
                Heartbeat("consumer"),
            ),
        )


async def run_worker(settings: AppSettings) -> None:
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    start_http_server(settings.metrics_port)
    try:
        await _run_loops(settings, stop)
    finally:
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.remove_signal_handler(sig)


async def _run_loops(settings: AppSettings, stop: asyncio.Event) -> None:
    async with worker_resources(settings) as resources:
        relay = asyncio.create_task(
            run_relay(resources.relay, stop, settings.relay_idle_seconds, Heartbeat("relay"))
        )
        consumer = asyncio.create_task(resources.consumer_loop.run(stop))
        loops = {relay, consumer}
        stopper = asyncio.create_task(stop.wait())
        await asyncio.wait({stopper, *loops}, return_when=asyncio.FIRST_COMPLETED)
        stop.set()
        stopper.cancel()
        done, pending = await asyncio.wait(loops, timeout=settings.drain_seconds)
        for task in pending:
            task.cancel()
        await asyncio.gather(*pending, return_exceptions=True)
        for task in done:
            task.result()


def main() -> None:
    configure_logging()
    asyncio.run(run_worker(AppSettings()))
```

`AppSettings` gains the fields the worker reads (`KAFKA_*` through `KafkaSettings`, `METRICS_PORT`, `DRAIN_SECONDS`,
`relay_idle_seconds`); the Helm chart already passes `METRICS_PORT` and `DRAIN_SECONDS` (`python-cd` §4), and the
bootstrap address goes in `values.yaml` `env:` as `KAFKA_BOOTSTRAP_SERVERS`. On a fresh cluster the worker may log
`Topic ... not found in cluster metadata` and `GroupCoordinatorNotAvailableError` for a few seconds until the broker
and the topic exist; the consumer retries and recovers without a restart.

## Broker container for tests
testcontainers' `KafkaContainer` targets Confluent images (it writes a Confluent start script). For
`apache/kafka` use a plain `DockerContainer` with the `KAFKA_*` environment of the image and a fixed host port, because
the advertised listener must already name the port the client will use:

### `tests/integration/kafka_container.py`

```python
import socket

from testcontainers.core.container import DockerContainer
from testcontainers.core.wait_strategies import LogMessageWaitStrategy

KAFKA_IMAGE = "apache/kafka:3.9.1"


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port: int = s.getsockname()[1]
    return port


class ApacheKafkaContainer(DockerContainer):
    def __init__(self, image: str = KAFKA_IMAGE) -> None:
        super().__init__(image)
        self.host_port = _free_port()
        self.with_bind_ports(9092, self.host_port)
        env = {
            "KAFKA_NODE_ID": "1",
            "KAFKA_PROCESS_ROLES": "broker,controller",
            "KAFKA_LISTENERS": "PLAINTEXT://:9092,CONTROLLER://:9093",
            "KAFKA_ADVERTISED_LISTENERS": f"PLAINTEXT://127.0.0.1:{self.host_port}",
            "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP": "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT",
            "KAFKA_CONTROLLER_LISTENER_NAMES": "CONTROLLER",
            "KAFKA_CONTROLLER_QUORUM_VOTERS": "1@localhost:9093",
            "KAFKA_INTER_BROKER_LISTENER_NAME": "PLAINTEXT",
            "KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR": "1",
            "KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR": "1",
            "KAFKA_TRANSACTION_STATE_LOG_MIN_ISR": "1",
            "KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS": "0",
        }
        for name, value in env.items():
            self.with_env(name, value)
        self.waiting_for(LogMessageWaitStrategy("Kafka Server started").with_startup_timeout(90))

    def get_bootstrap_server(self) -> str:
        return f"127.0.0.1:{self.host_port}"
```

Session fixture (add to `tests/integration/conftest.py`; `TEST_KAFKA_BOOTSTRAP_SERVERS` points at an existing broker, for
example a CI service container):

```python
@pytest.fixture(scope="session")
def bootstrap_servers() -> Iterator[str]:
    if external := os.environ.get("TEST_KAFKA_BOOTSTRAP_SERVERS"):
        yield external
        return
    if not _docker_available():
        pytest.skip("Docker is not available: integration tests skipped")
    with ApacheKafkaContainer() as kafka:
        yield kafka.get_bootstrap_server()
```

## End-to-end tests: the worker as a real process
The worker is started as a subprocess (`python -c "from my_service.worker import main; main()"`) with environment
variables only, so the test exercises `AppSettings`, the signal handlers and the shutdown path for real.
Add `patch = ["subprocess"]` under `[tool.coverage.run]` so the worker's lines count towards `fail_under`.

### `tests/integration/test_worker_kafka.py`

```python
import asyncio
import json
import os
import signal
import socket
import subprocess
import sys
import time
from collections.abc import Awaitable, Callable, Iterator
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from aiokafka import AIOKafkaConsumer, AIOKafkaProducer
from sqlalchemy import func, select
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import AsyncEngine, async_sessionmaker

from my_service.models.events import OrderPlaced
from my_service.repositories.orm import OrderRow, OutboxRow, ProcessedMessageRow

WORKER_CODE = "from my_service.worker import main; main()"


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port: int = s.getsockname()[1]
    return port


async def eventually(check: Callable[[], Awaitable[bool]], within_seconds: float = 60.0) -> None:
    deadline = time.monotonic() + within_seconds
    while time.monotonic() < deadline:
        if await check():
            return
        await asyncio.sleep(0.25)
    pytest.fail("condition not met before the deadline")


class WorkerProcess:
    def __init__(self, process: subprocess.Popen[bytes], heartbeat_dir: Path) -> None:
        self.process = process
        self.heartbeat_dir = heartbeat_dir

    def terminate_and_wait(self, timeout: float = 20.0) -> int:
        self.process.send_signal(signal.SIGTERM)
        return self.process.wait(timeout=timeout)


@pytest.fixture
def start_worker(
    postgres_url: str, bootstrap_servers: str, tmp_path: Path
) -> Iterator[Callable[[str], WorkerProcess]]:
    started: list[WorkerProcess] = []
    url = make_url(postgres_url)

    def start(topic: str) -> WorkerProcess:
        env = {
            **os.environ,
            "DB_URL": url.set(password=None).render_as_string(),
            "DB_PASSWORD": url.password or "",
            "KAFKA_BOOTSTRAP_SERVERS": bootstrap_servers,
            "KAFKA_GROUP_ID": f"worker-{uuid4()}",
            "KAFKA_TOPICS": json.dumps([topic]),
            "METRICS_PORT": str(_free_port()),
            "HEARTBEAT_DIR": str(tmp_path),
            "PYTHONUNBUFFERED": "1",
        }
        process = subprocess.Popen([sys.executable, "-c", WORKER_CODE], env=env)  # noqa: S603
        worker = WorkerProcess(process, tmp_path)
        started.append(worker)
        return worker

    yield start
    for worker in started:
        if worker.process.poll() is None:
            worker.process.kill()
            worker.process.wait()


def _placed(order_id: UUID, event_id: UUID) -> OrderPlaced:
    return OrderPlaced(
        event_id=event_id,
        occurred_at=datetime.now(UTC),
        order_id=order_id,
        customer_id="c-1",
        total_cents=5,
    )


async def _order_status(engine: AsyncEngine, order_id: UUID) -> str | None:
    factory = async_sessionmaker(engine)
    async with factory() as session:
        return await session.scalar(select(OrderRow.status).where(OrderRow.id == order_id))


async def test_worker_outboxToConsumer_thenSigtermExitsZero(
    engine: AsyncEngine,
    start_worker: Callable[[str], WorkerProcess],
    clean_tables: None,
) -> None:
    topic = f"orders.test-{uuid4()}"
    order_id, event_id = uuid4(), uuid4()
    factory = async_sessionmaker(engine, expire_on_commit=False)
    event = _placed(order_id, event_id)
    async with factory() as s, s.begin():
        s.add(OrderRow(id=order_id, customer_id="c-1", total_cents=5, status="new"))
        s.add(
            OutboxRow(
                id=event_id,
                topic=topic,
                key=event.key(),
                event_type="OrderPlaced",
                payload=event.model_dump(mode="json"),
            )
        )
    worker = start_worker(topic)

    async def received() -> bool:
        return await _order_status(engine, order_id) == "received"

    await eventually(received)
    async with factory() as s:
        published = await s.scalar(select(OutboxRow.published_at).where(OutboxRow.id == event_id))
        claims = await s.scalar(select(func.count()).select_from(ProcessedMessageRow))
    assert published is not None
    assert claims == 1
    started = time.monotonic()
    assert worker.terminate_and_wait() == 0
    assert time.monotonic() - started < 10
    assert {p.name for p in worker.heartbeat_dir.iterdir()} == {"relay", "consumer"}


async def test_worker_poisonMessages_goToDeadLetterTopic(
    engine: AsyncEngine,
    bootstrap_servers: str,
    start_worker: Callable[[str], WorkerProcess],
    clean_tables: None,
) -> None:
    topic = f"orders.test-{uuid4()}"
    worker = start_worker(topic)
    async with AIOKafkaProducer(bootstrap_servers=bootstrap_servers) as producer:
        await producer.send_and_wait(topic, value=b"{}", key=b"k1")
        await producer.send_and_wait(
            topic, value=b"not json", key=b"k2", headers=[("event_id", str(uuid4()).encode())]
        )
    async with AIOKafkaConsumer(
        f"{topic}.dlt",
        bootstrap_servers=bootstrap_servers,
        group_id=f"dlt-{uuid4()}",
        auto_offset_reset="earliest",
    ) as dlt:
        reasons: list[str] = []
        async with asyncio.timeout(60):
            while len(reasons) < 2:
                batch = await dlt.getmany(timeout_ms=1000)
                reasons.extend(
                    dict(r.headers)["dlt_reason"].decode() for rs in batch.values() for r in rs
                )
    assert sorted(reasons) == ["ValidationError", "missing or malformed event_id"]
    assert worker.terminate_and_wait() == 0


async def test_worker_duplicateDelivery_isClaimedOnce(
    engine: AsyncEngine,
    bootstrap_servers: str,
    start_worker: Callable[[str], WorkerProcess],
    clean_tables: None,
) -> None:
    topic = f"orders.test-{uuid4()}"
    duplicate_order, last_order, event_id = uuid4(), uuid4(), uuid4()
    factory = async_sessionmaker(engine, expire_on_commit=False)
    async with factory() as s, s.begin():
        s.add(OrderRow(id=duplicate_order, customer_id="c-1", total_cents=5, status="new"))
        s.add(OrderRow(id=last_order, customer_id="c-1", total_cents=5, status="new"))
    worker = start_worker(topic)
    first = _placed(duplicate_order, event_id).model_dump_json().encode()
    last = _placed(last_order, uuid4()).model_dump_json().encode()
    async with AIOKafkaProducer(bootstrap_servers=bootstrap_servers) as producer:
        for value, eid in ((first, event_id), (first, event_id), (last, None)):
            headers = [("event_id", str(eid or json.loads(value)["event_id"]).encode())]
            await producer.send_and_wait(topic, value=value, key=b"k", headers=headers)

    async def last_received() -> bool:
        return await _order_status(engine, last_order) == "received"

    await eventually(last_received)
    async with factory() as s:
        claims = await s.scalar(
            select(func.count())
            .select_from(ProcessedMessageRow)
            .where(ProcessedMessageRow.message_id == event_id)
        )
    assert claims == 1
    assert worker.terminate_and_wait() == 0
```

Unit tests for the loop (`tests/unit/test_consumer_loop.py`, fakes only) cover success, retry-then-success,
always-failing (dead-lettered and committed), a missing or malformed `event_id`, and `stop` set while idle. Real-database
tests (`tests/integration/test_idempotent_consumer.py`) assert that a message handled twice runs the handler once and
that a failing handler leaves the message claimable.

## Unit tests for the loops and the publisher

Fakes only (`tests/fakes/messaging.py`, in `python-unit-tests`' `test-support.md`): success, retry-then-success, always-failing, missing and malformed `event_id`, `stop` while idle, a failing relay batch, the idle wait and the heartbeat. The worker's own drain tests are in `python-graceful-shutdown`'s `worker-units.md`.

### `tests/unit/test_consumer_loop.py`

```python
import asyncio
from pathlib import Path
from uuid import UUID

import pytest

from my_service import liveness
from my_service.liveness import Heartbeat
from my_service.messaging.consumer_loop import ConsumerLoop
from tests.fakes.messaging import (
    FakeMessageConsumer,
    FakePublisher,
    FakeRecord,
    FakeSource,
    a_record,
)

EVENT_ID = UUID(int=7)


@pytest.fixture(autouse=True)
def heartbeat_dir(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    monkeypatch.setattr(liveness, "HEARTBEAT_DIR", tmp_path)
    return tmp_path


def _loop(
    source: FakeSource, consumer: FakeMessageConsumer, dead_letters: FakePublisher
) -> ConsumerLoop:
    return ConsumerLoop(
        source, consumer, dead_letters, Heartbeat("consumer"), max_attempts=3, retry_delay_seconds=0
    )


async def test_run_successfulRecord_isHandledOnceAndCommitted(heartbeat_dir: Path) -> None:
    stop = asyncio.Event()
    source = FakeSource([[a_record()]], stop)
    consumer, dead_letters = FakeMessageConsumer(), FakePublisher()
    await _loop(source, consumer, dead_letters).run(stop)
    assert consumer.handled == [(EVENT_ID, b"{}")]
    assert source.commits == 1
    assert dead_letters.published == []
    assert (heartbeat_dir / "consumer").exists()


async def test_run_handlerFailsTwiceThenSucceeds_isRetriedWithoutDeadLetter() -> None:
    stop = asyncio.Event()
    source = FakeSource([[a_record()]], stop)
    consumer, dead_letters = FakeMessageConsumer(failures=2), FakePublisher()
    await _loop(source, consumer, dead_letters).run(stop)
    assert consumer.attempts == 3
    assert len(consumer.handled) == 1
    assert dead_letters.published == []
    assert source.commits == 1


async def test_run_handlerAlwaysFails_isDeadLetteredWithReasonAndStillCommitted() -> None:
    stop = asyncio.Event()
    source = FakeSource([[a_record(value=b"payload")]], stop)
    consumer, dead_letters = FakeMessageConsumer(failures=99), FakePublisher()
    await _loop(source, consumer, dead_letters).run(stop)
    assert consumer.attempts == 3
    topic, key, value, headers = dead_letters.published[0]
    assert (topic, key, value) == ("orders.order-placed.v1.dlt", "k", b"payload")
    assert headers["dlt_reason"] == "RuntimeError"
    assert headers["event_id"] == str(EVENT_ID)
    assert source.commits == 1


@pytest.mark.parametrize("event_id", [None, "not-a-uuid"], ids=["missing", "malformed"])
async def test_run_badEventId_goesStraightToDeadLetterWithoutHandling(
    event_id: str | None,
) -> None:
    stop = asyncio.Event()
    source = FakeSource([[a_record(event_id=event_id)]], stop)
    consumer, dead_letters = FakeMessageConsumer(), FakePublisher()
    await _loop(source, consumer, dead_letters).run(stop)
    assert consumer.attempts == 0
    assert dead_letters.published[0][3]["dlt_reason"] == "missing or malformed event_id"
    assert source.commits == 1


async def test_run_recordWithoutKeyOrValue_isDeadLetteredWithEmptyKey() -> None:
    stop = asyncio.Event()
    source = FakeSource([[FakeRecord(key=None, value=None)]], stop)
    dead_letters = FakePublisher()
    await _loop(source, FakeMessageConsumer(), dead_letters).run(stop)
    assert dead_letters.published[0][1:3] == ("", b"")


async def test_run_idleThenStopSet_returnsWithinOnePoll() -> None:
    stop = asyncio.Event()
    source = FakeSource([], stop)
    await asyncio.wait_for(_loop(source, FakeMessageConsumer(), FakePublisher()).run(stop), 1)
    assert source.polls == 1
    assert source.commits == 0
```

### `tests/unit/test_outbox_relay_loop.py`

```python
import asyncio
from pathlib import Path

import pytest

from my_service import liveness
from my_service.liveness import Heartbeat
from my_service.messaging.kafka_publisher import KafkaEventPublisher
from my_service.messaging.outbox_relay import run_relay


class ScriptedRelay:
    def __init__(self, results: list[int | Exception], stop: asyncio.Event) -> None:
        self._results = results
        self._stop = stop
        self.batches = 0

    async def publish_batch(self) -> int:
        self.batches += 1
        if not self._results:
            self._stop.set()
            return 0
        result = self._results.pop(0)
        if isinstance(result, Exception):
            raise result
        return result


async def _run(results: list[int | Exception], idle: float = 0) -> ScriptedRelay:
    stop = asyncio.Event()
    relay = ScriptedRelay(results, stop)
    await asyncio.wait_for(run_relay(relay, stop, idle), 2)
    return relay


async def test_runRelay_batchesWithRows_runBackToBackUntilStopped() -> None:
    relay = await _run([3, 2])
    assert relay.batches == 3


async def test_runRelay_failingBatch_isLoggedAndTheLoopKeepsGoing() -> None:
    relay = await _run([RuntimeError("db down"), 1])
    assert relay.batches == 3


async def test_runRelay_emptyBatch_waitsForTheIdleIntervalButWakesOnStop() -> None:
    stop = asyncio.Event()
    relay = ScriptedRelay([0], stop)
    task = asyncio.create_task(run_relay(relay, stop, idle_seconds=60))
    await asyncio.sleep(0.05)
    assert relay.batches == 1
    stop.set()
    await asyncio.wait_for(task, 1)


async def test_runRelay_beatsItsHeartbeatEveryIteration(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(liveness, "HEARTBEAT_DIR", tmp_path)
    stop = asyncio.Event()
    relay = ScriptedRelay([1], stop)
    await run_relay(relay, stop, 0, Heartbeat("relay"))
    assert (tmp_path / "relay").exists()


class FakeProducer:
    def __init__(self) -> None:
        self.sent: list[tuple[str, bytes, bytes, list[tuple[str, bytes]]]] = []

    async def send_and_wait(
        self, topic: str, value: bytes, key: bytes, headers: list[tuple[str, bytes]]
    ) -> None:
        self.sent.append((topic, value, key, headers))


async def test_kafkaEventPublisher_encodesKeyAndHeadersAndWaitsForTheBroker() -> None:
    producer = FakeProducer()
    await KafkaEventPublisher(producer).publish("t", "k", b"v", {"event_id": "e1"})
    assert producer.sent == [("t", b"v", b"k", [("event_id", b"e1")])]
```

## Integration tests against PostgreSQL

The relay never needs a broker: a fake publisher records what the relay would send.

### `tests/integration/test_outbox_relay.py`

```python
import asyncio
from uuid import UUID, uuid4

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncEngine, async_sessionmaker

from my_service.messaging.outbox_relay import RELAY_LOCK_KEY, OutboxRelay
from my_service.repositories.orm import OutboxRow
from tests.fakes.messaging import FakePublisher


async def _add_events(engine: AsyncEngine, count: int) -> list[UUID]:
    ids = [uuid4() for _ in range(count)]
    for n, event_id in enumerate(ids):
        async with async_sessionmaker(engine)() as s, s.begin():
            s.add(
                OutboxRow(id=event_id, topic="t", key=f"agg-{n}", event_type="E", payload={"n": n})
            )
    return ids


async def _unpublished(engine: AsyncEngine) -> int:
    async with async_sessionmaker(engine)() as s:
        return (
            await s.scalar(
                select(func.count()).select_from(OutboxRow).where(OutboxRow.published_at.is_(None))
            )
            or 0
        )


async def test_publishBatch_publishesInCreationOrderAndMarksRowsPublished(
    engine: AsyncEngine, clean_tables: None
) -> None:
    ids = await _add_events(engine, 3)
    publisher = FakePublisher()
    relay = OutboxRelay(async_sessionmaker(engine), publisher, batch_size=10)
    assert await relay.publish_batch() == 3
    assert [headers["event_id"] for *_, headers in publisher.published] == [str(i) for i in ids]
    assert await _unpublished(engine) == 0
    assert await relay.publish_batch() == 0


async def test_publishBatch_batchSizeBoundsTheRowsPerRound(
    engine: AsyncEngine, clean_tables: None
) -> None:
    await _add_events(engine, 5)
    relay = OutboxRelay(async_sessionmaker(engine), FakePublisher(), batch_size=2)
    assert await relay.publish_batch() == 2
    assert await _unpublished(engine) == 3


async def test_publishBatch_failingPublisher_leavesRowsUnpublishedForTheNextRound(
    engine: AsyncEngine, clean_tables: None
) -> None:
    await _add_events(engine, 2)
    failing = FakePublisher(fail=True)
    relay = OutboxRelay(async_sessionmaker(engine), failing, batch_size=10)
    with pytest.raises(RuntimeError):
        await relay.publish_batch()
    assert await _unpublished(engine) == 2
    failing.fail = False
    assert await relay.publish_batch() == 2


async def test_publishBatch_anotherRelayHoldsTheLock_publishesNothingUntilItIsReleased(
    engine: AsyncEngine, clean_tables: None
) -> None:
    await _add_events(engine, 2)
    publisher = FakePublisher()
    relay = OutboxRelay(async_sessionmaker(engine), publisher, batch_size=10)
    async with engine.connect() as holder:
        await holder.execute(select(func.pg_advisory_lock(RELAY_LOCK_KEY)))
        first, second = await asyncio.gather(relay.publish_batch(), relay.publish_batch())
        assert first == second == 0
        assert publisher.published == []
        await holder.execute(select(func.pg_advisory_unlock(RELAY_LOCK_KEY)))
    assert await relay.publish_batch() == 2


async def test_publishBatch_rowsLockedByAnotherTransaction_areSkipped(
    engine: AsyncEngine, clean_tables: None
) -> None:
    ids = await _add_events(engine, 2)
    publisher = FakePublisher()
    relay = OutboxRelay(async_sessionmaker(engine), publisher, batch_size=10)
    async with async_sessionmaker(engine)() as locker, locker.begin():
        await locker.execute(select(OutboxRow).where(OutboxRow.id == ids[0]).with_for_update())
        assert await relay.publish_batch() == 1
    assert publisher.published[0][3]["event_id"] == str(ids[1])
```

### `tests/integration/test_idempotent_consumer.py`

```python
from uuid import UUID, uuid4

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from my_service.messaging.handlers import mark_order_received
from my_service.messaging.idempotent_consumer import IdempotentConsumer
from my_service.models.events import OrderPlaced
from my_service.repositories.orm import OrderRow, ProcessedMessageRow
from tests.fakes.doubles import FIXED_NOW


def _placed(order_id: UUID) -> bytes:
    event = OrderPlaced(
        event_id=uuid4(),
        occurred_at=FIXED_NOW,
        order_id=order_id,
        customer_id="c-1",
        total_cents=5,
    )
    return event.model_dump_json().encode()


async def _seed_order(engine: AsyncEngine) -> UUID:
    order_id = uuid4()
    async with async_sessionmaker(engine)() as s, s.begin():
        s.add(OrderRow(id=order_id, customer_id="c-1", total_cents=5, status="new"))
    return order_id


async def _status(engine: AsyncEngine, order_id: UUID) -> str | None:
    async with async_sessionmaker(engine)() as s:
        return await s.scalar(select(OrderRow.status).where(OrderRow.id == order_id))


async def _claims(engine: AsyncEngine) -> int:
    async with async_sessionmaker(engine)() as s:
        return await s.scalar(select(func.count()).select_from(ProcessedMessageRow)) or 0


async def test_handle_sameMessageTwice_runsTheHandlerOnce(
    engine: AsyncEngine, clean_tables: None
) -> None:
    order_id = await _seed_order(engine)
    calls: list[int] = []

    async def handler(session: AsyncSession, value: bytes) -> None:
        calls.append(1)
        await mark_order_received(session, value)

    consumer = IdempotentConsumer(async_sessionmaker(engine), "billing", handler)
    message_id, value = uuid4(), _placed(order_id)
    assert await consumer.handle(message_id, value) is True
    assert await consumer.handle(message_id, value) is False
    assert calls == [1]
    assert await _status(engine, order_id) == "received"
    assert await _claims(engine) == 1


async def test_handle_failingHandler_rollsBackTheClaimSoRedeliveryIsProcessed(
    engine: AsyncEngine, clean_tables: None
) -> None:
    order_id = await _seed_order(engine)
    attempts: list[int] = []

    async def flaky(session: AsyncSession, value: bytes) -> None:
        attempts.append(1)
        if len(attempts) == 1:
            raise RuntimeError("transient")
        await mark_order_received(session, value)

    consumer = IdempotentConsumer(async_sessionmaker(engine), "billing", flaky)
    message_id, value = uuid4(), _placed(order_id)
    with pytest.raises(RuntimeError):
        await consumer.handle(message_id, value)
    assert await _claims(engine) == 0
    assert await consumer.handle(message_id, value) is True
    assert await _status(engine, order_id) == "received"


async def test_handle_sameMessageIdForDifferentConsumers_isClaimedByEach(
    engine: AsyncEngine, clean_tables: None
) -> None:
    async def noop(session: AsyncSession, value: bytes) -> None:
        return None

    message_id = uuid4()
    for name in ("billing", "shipping"):
        consumer = IdempotentConsumer(async_sessionmaker(engine), name, noop)
        assert await consumer.handle(message_id, b"{}") is True
    assert await _claims(engine) == 2
```


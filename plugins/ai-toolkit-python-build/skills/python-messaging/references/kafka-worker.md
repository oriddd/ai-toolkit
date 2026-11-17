# python-messaging — consumer loop, worker and real-Kafka tests

Back to [`SKILL.md`](../SKILL.md). Every file here ran against a real `apache/kafka:3.9.1` and PostgreSQL
(testcontainers): the outbox row reached the topic through the relay, the consumer handled it once, poison
messages landed on `<topic>.dlt`, and `SIGTERM` stopped the worker process with exit code 0 and both heartbeat files.

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
        except KeyError, ValueError:
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

from aiokafka import AIOKafkaConsumer, AIOKafkaProducer
from prometheus_client import start_http_server
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from my_service.config.settings import AppSettings
from my_service.liveness import Heartbeat
from my_service.messaging.consumer_loop import ConsumerLoop
from my_service.messaging.handlers import mark_order_received
from my_service.messaging.idempotent_consumer import IdempotentConsumer
from my_service.messaging.kafka_publisher import KafkaEventPublisher
from my_service.messaging.outbox_relay import OutboxRelay, run_relay
from my_service.observability.logging import configure_logging


@dataclass(frozen=True)
class WorkerResources:
    relay: OutboxRelay
    consumer_loop: ConsumerLoop


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

# python-integration-tests — conftest, migrations, repository and API tests

Back to [`SKILL.md`](../SKILL.md) §1 to §3. The marker hook, the session-scoped containers (PostgreSQL, and the Kafka
broker of `python-messaging` when the service has a worker), the migrated `engine`, the savepoint `session`, the
`clean_tables` cleanup, and the tests that need a real PostgreSQL. A service without messaging drops the
`bootstrap_servers` fixture and the `kafka_container` import.

Colima and Rancher Desktop: `export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock` (see the skill).

## Fixtures

### `tests/conftest.py`

```python
import pytest


def pytest_collection_modifyitems(items: list[pytest.Item]) -> None:
    for item in items:
        if "integration" in item.path.parts:
            item.add_marker(pytest.mark.integration)
```

### `tests/integration/conftest.py`

```python
import os
from collections.abc import AsyncIterator, Iterator

import docker
import pytest
from alembic import command
from alembic.config import Config
from docker.errors import DockerException
from sqlalchemy import Connection
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, create_async_engine
from testcontainers.community.postgres import PostgresContainer

from my_service.repositories.orm import Base
from tests.integration.kafka_container import ApacheKafkaContainer


def _docker_available() -> bool:
    try:
        docker.from_env().ping()
    except DockerException:
        return False
    return True


@pytest.fixture(scope="session")
def postgres_url() -> Iterator[str]:
    if external := os.environ.get("TEST_DATABASE_URL"):
        yield external
        return
    if not _docker_available():
        if os.environ.get("CI"):
            pytest.fail("integration tests need Docker in CI")
        pytest.skip("Docker is not available: integration tests skipped")
    with PostgresContainer("postgres:16-alpine", driver="asyncpg") as pg:
        yield pg.get_connection_url()


async def run_alembic_upgrade(engine: AsyncEngine) -> None:
    def upgrade(connection: Connection) -> None:
        config = Config("alembic.ini")
        config.attributes["connection"] = connection
        command.upgrade(config, "head")

    async with engine.begin() as conn:
        await conn.run_sync(upgrade)


@pytest.fixture(scope="session")
async def engine(postgres_url: str) -> AsyncIterator[AsyncEngine]:
    engine = create_async_engine(postgres_url)
    await run_alembic_upgrade(engine)
    yield engine
    await engine.dispose()


@pytest.fixture
async def session(engine: AsyncEngine) -> AsyncIterator[AsyncSession]:
    async with engine.connect() as conn:
        tx = await conn.begin()
        async with AsyncSession(bind=conn, join_transaction_mode="create_savepoint") as s:
            yield s
        await tx.rollback()


@pytest.fixture(scope="session")
def bootstrap_servers() -> Iterator[str]:
    if external := os.environ.get("TEST_KAFKA_BOOTSTRAP_SERVERS"):
        yield external
        return
    if not _docker_available():
        pytest.skip("Docker is not available: integration tests skipped")
    with ApacheKafkaContainer() as kafka:
        yield kafka.get_bootstrap_server()


@pytest.fixture
async def clean_tables(engine: AsyncEngine) -> AsyncIterator[None]:
    yield
    async with engine.begin() as conn:
        for table in reversed(Base.metadata.sorted_tables):
            await conn.execute(table.delete())
```

## Tests

### `tests/integration/test_migrations.py`

```python
from alembic import command
from alembic.config import Config
from sqlalchemy import Connection, inspect
from sqlalchemy.ext.asyncio import AsyncEngine


async def test_migrations_head_matchesModels(engine: AsyncEngine) -> None:
    def check(connection: Connection) -> None:
        config = Config("alembic.ini")
        config.attributes["connection"] = connection
        command.check(config)

    async with engine.connect() as conn:
        await conn.run_sync(check)


async def test_migrations_downgradeToBaseAndUpgrade_roundTrips(engine: AsyncEngine) -> None:
    def round_trip(connection: Connection) -> list[str]:
        config = Config("alembic.ini")
        config.attributes["connection"] = connection
        command.downgrade(config, "base")
        tables_after_downgrade = inspect(connection).get_table_names()
        command.upgrade(config, "head")
        return tables_after_downgrade

    async with engine.begin() as conn:
        assert await conn.run_sync(round_trip) == ["alembic_version"]
```

### `tests/integration/test_sql_order_repository.py`

```python
from uuid import UUID

import pytest
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from my_service.errors.domain import (
    OrderAlreadyExistsError,
    OrderNotFoundError,
    OrderVersionConflictError,
)
from my_service.models.events import OrderPlaced
from my_service.models.order import Order
from my_service.repositories.order_repository import SqlOrderRepository
from my_service.repositories.unit_of_work import SqlUnitOfWork
from tests.fakes.doubles import FIXED_NOW, an_order


async def test_add_thenGet_roundTrips(session: AsyncSession) -> None:
    repo = SqlOrderRepository(session)
    order = an_order()
    await repo.add(order)
    assert await repo.get(order.id) == order


async def test_add_duplicateId_raisesOrderAlreadyExists(session: AsyncSession) -> None:
    repo = SqlOrderRepository(session)
    await repo.add(an_order())
    with pytest.raises(OrderAlreadyExistsError):
        await repo.add(an_order())


async def test_get_unknownId_raisesOrderNotFound(session: AsyncSession) -> None:
    with pytest.raises(OrderNotFoundError):
        await SqlOrderRepository(session).get(UUID(int=404))


async def test_save_returnsNewVersionAndPersistsChanges(session: AsyncSession) -> None:
    repo = SqlOrderRepository(session)
    order = an_order()
    await repo.add(order)
    assert await repo.save(order.pay(), expected_version=1) == 2
    stored = await repo.get(order.id)
    assert (stored.status, stored.version) == ("paid", 2)


async def test_save_staleVersion_raisesOrderVersionConflictError(session: AsyncSession) -> None:
    repo = SqlOrderRepository(session)
    order = an_order()
    await repo.add(order)
    await repo.save(order.pay(), expected_version=1)
    with pytest.raises(OrderVersionConflictError):
        await repo.save(order, expected_version=1)


async def test_save_identicalPutTwice_stillBumpsTheVersion(session: AsyncSession) -> None:
    repo = SqlOrderRepository(session)
    order = an_order()
    await repo.add(order)
    assert await repo.save(order, expected_version=1) == 2
    assert await repo.save(order, expected_version=2) == 3


async def test_listByCustomer_isBoundedAndFiltered(session: AsyncSession) -> None:
    repo = SqlOrderRepository(session)
    for n in range(3):
        await repo.add(Order(UUID(int=10 + n), "c-1", 5, "new"))
    await repo.add(Order(UUID(int=99), "other", 5, "new"))
    assert len(await repo.list_by_customer("c-1", limit=2)) == 2
    assert len(await repo.list_by_customer("c-1", limit=10)) == 3


async def test_unitOfWork_orderAndOutboxEventCommitTogether(
    engine: AsyncEngine, clean_tables: None
) -> None:
    factory = async_sessionmaker(engine, expire_on_commit=False)
    order = an_order()
    async with SqlUnitOfWork(factory) as uow:
        await uow.orders.add(order)
        uow.outbox.add(
            OrderPlaced(
                event_id=UUID(int=5),
                occurred_at=FIXED_NOW,
                order_id=order.id,
                customer_id=order.customer_id,
                total_cents=order.total_cents,
            )
        )
        await uow.commit()
    async with SqlUnitOfWork(factory) as uow:
        assert await uow.orders.get(order.id) == order


async def test_unitOfWork_exceptionInsideBlock_rollsBackTheOrder(
    engine: AsyncEngine, clean_tables: None
) -> None:
    factory = async_sessionmaker(engine, expire_on_commit=False)
    order = an_order()
    with pytest.raises(RuntimeError):
        async with SqlUnitOfWork(factory) as uow:
            await uow.orders.add(order)
            raise RuntimeError("abort")
    async with SqlUnitOfWork(factory) as uow:
        with pytest.raises(OrderNotFoundError):
            await uow.orders.get(order.id)
```

### `tests/integration/test_orders_api.py`

```python
from collections.abc import AsyncIterator

import pytest
from asgi_lifespan import LifespanManager
from httpx import ASGITransport, AsyncClient
from pydantic import SecretStr
from sqlalchemy import func, select
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import AsyncEngine, async_sessionmaker

from my_service.api.dependencies import get_billing_gateway, get_token_verifier
from my_service.config.settings import AppSettings, DatabaseSettings
from my_service.main import create_app
from my_service.models.principal import Principal
from my_service.repositories.orm import OutboxRow
from tests.fakes.doubles import FakeBillingGateway, FakeTokenVerifier

AUTH = {"Authorization": "Bearer writer"}
NEW_ORDER = {"customer_email": "a@b.co", "customer_id": "c-1", "total_cents": 10}


@pytest.fixture
async def client(
    postgres_url: str, engine: AsyncEngine, clean_tables: None
) -> AsyncIterator[AsyncClient]:
    url = make_url(postgres_url)
    settings = AppSettings(
        db=DatabaseSettings(
            url=url.set(password=None).render_as_string(), password=SecretStr(url.password or "")
        ),
        redis_url="redis://127.0.0.1:1",
    )
    app = create_app(settings)
    verifier = FakeTokenVerifier(
        {"writer": Principal("u1", frozenset({"orders:read", "orders:write"}))}
    )
    app.dependency_overrides[get_token_verifier] = lambda: verifier
    app.dependency_overrides[get_billing_gateway] = lambda: FakeBillingGateway({"c-1": 100})
    async with (
        LifespanManager(app),
        AsyncClient(transport=ASGITransport(app=app), base_url="http://t") as http,
    ):
        yield http


async def test_createThenPay_commitsOrderAndEventAndVersionsTheUpdate(
    client: AsyncClient, engine: AsyncEngine
) -> None:
    created = await client.post("/v1/orders", headers=AUTH, json=NEW_ORDER)
    assert created.status_code == 201
    order_id = created.json()["id"]
    async with async_sessionmaker(engine)() as s:
        assert await s.scalar(select(func.count()).select_from(OutboxRow)) == 1
    paid = await client.post(f"/v1/orders/{order_id}/pay", headers=AUTH, json={"version": 1})
    assert paid.json() == {"id": order_id, "status": "paid", "version": 2}
    stale = await client.post(f"/v1/orders/{order_id}/pay", headers=AUTH, json={"version": 1})
    assert stale.status_code == 409
    assert stale.json()["code"] == "ORDER_VERSION_CONFLICT"


async def test_get_redisUnreachable_failsOpenToTheDatabase(client: AsyncClient) -> None:
    created = await client.post("/v1/orders", headers=AUTH, json=NEW_ORDER)
    fetched = await client.get(f"/v1/orders/{created.json()['id']}", headers=AUTH)
    assert fetched.status_code == 200
    assert fetched.json()["status"] == "new"


async def test_healthReady_databaseReachable_isUp(client: AsyncClient) -> None:
    assert (await client.get("/health/ready")).json() == {"status": "UP"}
```

# python-unit-tests — fakes, doubles, shared fixtures and the HTTP-layer tests

Back to [`SKILL.md`](../SKILL.md) §3, §4 and §6. Every directory under `tests/` has an `__init__.py`, so
`from tests.fakes.in_memory import ...` resolves under pytest and mypy sees each module once. The in-memory unit of
work has an `outbox` fake mirroring `UnitOfWork.outbox`, and the in-memory repository enforces optimistic locking like
the SQL one.

## Fakes

### `tests/fakes/in_memory.py`

```python
from types import TracebackType
from typing import Self
from uuid import UUID

from my_service.errors.domain import (
    OrderAlreadyExistsError,
    OrderNotFoundError,
    OrderVersionConflictError,
)
from my_service.models.events import DomainEvent
from my_service.models.order import Order
from my_service.repositories.order_repository import OrderRepository
from my_service.repositories.outbox import Outbox


class InMemoryOrderRepository:
    def __init__(self) -> None:
        self.rows: dict[UUID, Order] = {}

    async def get(self, order_id: UUID) -> Order:
        if order_id not in self.rows:
            raise OrderNotFoundError(order_id=order_id)
        return self.rows[order_id]

    async def add(self, order: Order) -> None:
        if order.id in self.rows:
            raise OrderAlreadyExistsError(order_id=order.id)
        self.rows[order.id] = order

    async def save(self, order: Order, expected_version: int) -> int:
        current = self.rows.get(order.id)
        if current is None:
            raise OrderNotFoundError(order_id=order.id)
        if current.version != expected_version:
            raise OrderVersionConflictError(order_id=order.id)
        new_version = expected_version + 1
        self.rows[order.id] = Order(
            order.id, order.customer_id, order.total_cents, order.status, new_version
        )
        return new_version

    async def list_by_customer(self, customer_id: str, limit: int) -> list[Order]:
        return [o for o in self.rows.values() if o.customer_id == customer_id][:limit]


class InMemoryOutbox:
    def __init__(self) -> None:
        self.events: list[DomainEvent] = []

    def add(self, event: DomainEvent) -> None:
        self.events.append(event)


class InMemoryUnitOfWork:
    def __init__(self, orders: InMemoryOrderRepository) -> None:
        self.orders: OrderRepository = orders
        self.outbox_store = InMemoryOutbox()
        self.outbox: Outbox = self.outbox_store
        self.committed = False

    async def __aenter__(self) -> Self:
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        return None

    async def commit(self) -> None:
        self.committed = True
```

### `tests/fakes/doubles.py`

```python
from collections.abc import Mapping
from datetime import UTC, datetime
from uuid import UUID

from my_service.errors.base import NotAuthenticatedError
from my_service.errors.domain import CustomerNotFoundError
from my_service.models.credit import CustomerCredit
from my_service.models.order import Order
from my_service.models.principal import Principal

FIXED_NOW = datetime(2026, 1, 1, tzinfo=UTC)


def an_order(*, total_cents: int = 1_000, customer_id: str = "c-1", status: str = "new") -> Order:
    return Order(UUID(int=1), customer_id, total_cents, status)


class FixedClock:
    def now(self) -> datetime:
        return FIXED_NOW


class SequentialIds:
    def __init__(self) -> None:
        self._next = 100

    def new_id(self) -> UUID:
        self._next += 1
        return UUID(int=self._next)


class FakeBillingGateway:
    def __init__(self, credits: Mapping[str, int] | None = None) -> None:
        self._credits = dict(credits or {})
        self.calls: list[str] = []

    async def get_credit(self, customer_id: str) -> CustomerCredit:
        self.calls.append(customer_id)
        if customer_id not in self._credits:
            raise CustomerNotFoundError(customer_id=customer_id)
        return CustomerCredit(customer_id, self._credits[customer_id])


class FakeTokenVerifier:
    def __init__(self, principals: Mapping[str, Principal]) -> None:
        self._principals = principals

    def verify(self, token: str) -> Principal:
        if token not in self._principals:
            raise NotAuthenticatedError()
        return self._principals[token]
```

### `tests/fakes/messaging.py`

```python
import asyncio
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from uuid import UUID


@dataclass(frozen=True)
class FakeRecord:
    topic: str = "orders.order-placed.v1"
    key: bytes | None = b"k"
    value: bytes | None = b"{}"
    headers: Sequence[tuple[str, bytes]] = ()


EVENT_ID = UUID(int=7)


def a_record(event_id: UUID | str | None = EVENT_ID, value: bytes = b"{}") -> FakeRecord:
    headers = [] if event_id is None else [("event_id", str(event_id).encode())]
    return FakeRecord(value=value, headers=headers)


class FakeSource:
    def __init__(self, batches: Sequence[Sequence[FakeRecord]], stop: asyncio.Event) -> None:
        self._batches = list(batches)
        self._stop = stop
        self.commits = 0
        self.polls = 0

    async def getmany(
        self, *, timeout_ms: int, max_records: int
    ) -> Mapping[object, Sequence[FakeRecord]]:
        self.polls += 1
        if not self._batches:
            self._stop.set()
            return {}
        return {"tp": self._batches.pop(0)}

    async def commit(self) -> None:
        self.commits += 1


class FakeMessageConsumer:
    def __init__(self, failures: int = 0) -> None:
        self.handled: list[tuple[UUID, bytes]] = []
        self.attempts = 0
        self._failures = failures

    async def handle(self, message_id: UUID, value: bytes) -> bool:
        self.attempts += 1
        if self.attempts <= self._failures:
            raise RuntimeError("handler failed")
        self.handled.append((message_id, value))
        return True


@dataclass
class FakePublisher:
    published: list[tuple[str, str, bytes, Mapping[str, str]]] = field(default_factory=list)
    fail: bool = False

    async def publish(self, topic: str, key: str, value: bytes, headers: Mapping[str, str]) -> None:
        if self.fail:
            raise RuntimeError("broker down")
        self.published.append((topic, key, value, dict(headers)))
```

### `tests/fakes/engine.py`

```python
from types import TracebackType
from typing import Self, cast

from sqlalchemy.ext.asyncio import AsyncEngine


class FakeConnection:
    def __init__(self, engine: FakeEngine) -> None:
        self._engine = engine

    async def __aenter__(self) -> Self:
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        return None

    async def scalar(self, statement: object) -> bool:
        name = str(statement).split("(")[0].removeprefix("SELECT ").strip()
        self._engine.statements.append(name)
        return self._engine.lock_free if name == "pg_try_advisory_lock" else True


class FakeEngine:
    def __init__(self, lock_free: bool = True) -> None:
        self.lock_free = lock_free
        self.statements: list[str] = []

    def connect(self) -> FakeConnection:
        return FakeConnection(self)

    def as_engine(self) -> AsyncEngine:
        return cast(AsyncEngine, self)
```

## Operation and HTTP-layer tests

### `tests/unit/test_create_order.py`

```python
from uuid import UUID

import pytest

from my_service.errors.domain import InsufficientCreditError
from my_service.models.events import OrderPlaced
from my_service.models.requests import CreateOrderRequest
from my_service.operations.create_order import CreateOrderOperation
from my_service.validation.rules import SufficientCreditRule
from tests.fakes.doubles import FIXED_NOW, FakeBillingGateway, FixedClock, SequentialIds
from tests.fakes.in_memory import InMemoryOrderRepository, InMemoryUnitOfWork


def _request(*, total_cents: int = 500) -> CreateOrderRequest:
    return CreateOrderRequest(customer_email="a@b.co", customer_id="c-1", total_cents=total_cents)


def _operation(
    repo: InMemoryOrderRepository, uow: list[InMemoryUnitOfWork], credit: int = 1_000
) -> CreateOrderOperation:
    def factory() -> InMemoryUnitOfWork:
        uow.append(InMemoryUnitOfWork(repo))
        return uow[-1]

    rule = SufficientCreditRule(FakeBillingGateway({"c-1": credit}))
    return CreateOrderOperation(factory, FixedClock(), SequentialIds(), [rule])


async def test_execute_validRequest_storesOrderAndOutboxEventInOneUnitOfWork() -> None:
    repo = InMemoryOrderRepository()
    units: list[InMemoryUnitOfWork] = []
    response = await _operation(repo, units).execute(_request())
    assert response.status == "new"
    assert repo.rows[response.id].total_cents == 500
    assert units[0].committed
    assert units[0].outbox_store.events == [
        OrderPlaced(
            event_id=UUID(int=102),
            occurred_at=FIXED_NOW,
            order_id=response.id,
            customer_id="c-1",
            total_cents=500,
        )
    ]


async def test_execute_creditTooLow_raisesAndStoresNothing() -> None:
    repo = InMemoryOrderRepository()
    units: list[InMemoryUnitOfWork] = []
    with pytest.raises(InsufficientCreditError):
        await _operation(repo, units, credit=499).execute(_request())
    assert repo.rows == {}
    assert units == []


async def test_execute_creditExactlyEnough_isAccepted() -> None:
    repo = InMemoryOrderRepository()
    await _operation(repo, [], credit=500).execute(_request())
    assert len(repo.rows) == 1
```

### `tests/unit/test_api.py`

```python
from collections.abc import AsyncIterator
from uuid import UUID

import pytest
from asgi_lifespan import LifespanManager
from httpx import ASGITransport, AsyncClient
from pydantic import SecretStr

from my_service.api.dependencies import (
    get_billing_gateway,
    get_token_verifier,
    get_uow_factory,
)
from my_service.config.settings import AppSettings, DatabaseSettings
from my_service.main import create_app
from my_service.models.principal import Principal
from tests.fakes.doubles import FakeBillingGateway, FakeTokenVerifier
from tests.fakes.in_memory import InMemoryOrderRepository, InMemoryUnitOfWork

SETTINGS = AppSettings(
    db=DatabaseSettings(url="postgresql+asyncpg://test@127.0.0.1:1/test", password=SecretStr("x")),
    redis_url="redis://127.0.0.1:1",
)
AUTH = {"Authorization": "Bearer good"}
READ_ONLY = {"Authorization": "Bearer reader"}
NEW_ORDER = {"customer_email": "A@B.co", "customer_id": "c-1", "total_cents": 10}


@pytest.fixture
def orders() -> InMemoryOrderRepository:
    return InMemoryOrderRepository()


@pytest.fixture
async def client(orders: InMemoryOrderRepository) -> AsyncIterator[AsyncClient]:
    app = create_app(SETTINGS)
    verifier = FakeTokenVerifier(
        {
            "good": Principal("u1", frozenset({"orders:read", "orders:write"})),
            "reader": Principal("u2", frozenset({"orders:read"})),
        }
    )
    app.dependency_overrides[get_uow_factory] = lambda: lambda: InMemoryUnitOfWork(orders)
    app.dependency_overrides[get_token_verifier] = lambda: verifier
    app.dependency_overrides[get_billing_gateway] = lambda: FakeBillingGateway({"c-1": 100})
    async with (
        LifespanManager(app),
        AsyncClient(
            transport=ASGITransport(app=app, raise_app_exceptions=False), base_url="http://t"
        ) as http,
    ):
        yield http


async def test_create_noToken_401WithChallenge(client: AsyncClient) -> None:
    response = await client.post("/v1/orders", json={})
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
    assert response.headers["content-type"] == "application/problem+json"
    assert "x-request-id" in response.headers


async def test_create_missingScope_403(client: AsyncClient) -> None:
    response = await client.post("/v1/orders", headers=READ_ONLY, json=NEW_ORDER)
    assert response.status_code == 403
    assert response.json()["code"] == "FORBIDDEN"


async def test_create_invalidBody_422DoesNotEchoInput(client: AsyncClient) -> None:
    response = await client.post(
        "/v1/orders", headers=AUTH, json={**NEW_ORDER, "total_cents": 0, "secret": "hunter2"}
    )
    assert response.status_code == 422
    assert "hunter2" not in response.text
    assert response.json()["code"] == "VALIDATION_FAILED"


async def test_create_insufficientCredit_409AndNothingStored(
    client: AsyncClient, orders: InMemoryOrderRepository
) -> None:
    response = await client.post("/v1/orders", headers=AUTH, json={**NEW_ORDER, "total_cents": 500})
    assert response.status_code == 409
    assert response.json()["code"] == "INSUFFICIENT_CREDIT"
    assert orders.rows == {}


async def test_createThenGetThenPay_roundTripWithCacheDown(client: AsyncClient) -> None:
    created = await client.post("/v1/orders", headers=AUTH, json=NEW_ORDER)
    assert created.status_code == 201
    order_id = UUID(created.json()["id"])
    assert created.headers["location"] == f"/v1/orders/{order_id}"
    fetched = await client.get(f"/v1/orders/{order_id}", headers=AUTH)
    assert fetched.json() == {"id": str(order_id), "status": "new", "version": 1}
    paid = await client.post(f"/v1/orders/{order_id}/pay", headers=AUTH, json={"version": 1})
    assert paid.json() == {"id": str(order_id), "status": "paid", "version": 2}


async def test_pay_staleVersion_409(client: AsyncClient) -> None:
    created = await client.post("/v1/orders", headers=AUTH, json=NEW_ORDER)
    order_id = created.json()["id"]
    response = await client.post(f"/v1/orders/{order_id}/pay", headers=AUTH, json={"version": 7})
    assert response.status_code == 409
    assert response.json()["code"] == "ORDER_VERSION_CONFLICT"


async def test_get_unknownOrder_404Problem(client: AsyncClient) -> None:
    response = await client.get(f"/v1/orders/{UUID(int=9)}", headers=AUTH)
    assert response.status_code == 404
    assert response.json()["code"] == "ORDER_NOT_FOUND"


async def test_unknownRoute_404Problem(client: AsyncClient) -> None:
    response = await client.get("/nope")
    assert response.status_code == 404
    assert response.headers["content-type"] == "application/problem+json"


async def test_unexpectedError_500WithoutLeakingTheMessage(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def boom(*_: object) -> None:
        raise RuntimeError("secret internals")

    monkeypatch.setattr(InMemoryOrderRepository, "get", boom)
    response = await client.get(f"/v1/orders/{UUID(int=9)}", headers=AUTH)
    assert response.status_code == 500
    assert "secret internals" not in response.text
    assert response.json()["code"] == "INTERNAL_ERROR"


async def test_healthLive_isUp(client: AsyncClient) -> None:
    assert (await client.get("/health/live")).json() == {"status": "UP"}


async def test_healthReady_databaseUnreachable_503(client: AsyncClient) -> None:
    response = await client.get("/health/ready")
    assert response.status_code == 503
    assert response.json() == {"status": "DOWN"}


async def test_metrics_servedWithTrailingSlash(client: AsyncClient) -> None:
    await client.get("/health/live")
    response = await client.get("/metrics/")
    assert response.status_code == 200
    assert 'route="/health/live"' in response.text


async def test_docs_offByDefault(client: AsyncClient) -> None:
    assert (await client.get("/docs")).status_code == 404
```

# python-persistence — cache-aside with a port

Back to [`SKILL.md`](../SKILL.md) §7. Redis sits behind the `Cache` Protocol; the use cases see `CacheAside[T]`
only, so the adapter can be swapped (in-memory fake in unit tests, Redis in production). Dependencies:
`redis>=5.0` (`redis.asyncio`, typed) and `testcontainers[redis]` in the dev group.

## Port, adapter, cache-aside
### `src/my_service/cache/port.py`

```python
from typing import Protocol


class CacheUnavailableError(Exception):
    pass


class Cache(Protocol):
    async def get(self, key: str) -> bytes | None: ...
    async def set(self, key: str, value: bytes, ttl_seconds: int) -> None: ...
    async def delete(self, key: str) -> None: ...
```

### `src/my_service/cache/redis_cache.py`

```python
from redis.asyncio import Redis
from redis.exceptions import RedisError

from my_service.cache.port import CacheUnavailableError


class RedisCache:
    def __init__(self, client: Redis) -> None:
        self._client = client

    async def get(self, key: str) -> bytes | None:
        try:
            raw = await self._client.get(key)
        except (RedisError, OSError, TimeoutError) as exc:
            raise CacheUnavailableError from exc
        return raw.encode() if isinstance(raw, str) else raw

    async def set(self, key: str, value: bytes, ttl_seconds: int) -> None:
        try:
            await self._client.set(key, value, ex=ttl_seconds)
        except (RedisError, OSError, TimeoutError) as exc:
            raise CacheUnavailableError from exc

    async def delete(self, key: str) -> None:
        try:
            await self._client.delete(key)
        except (RedisError, OSError, TimeoutError) as exc:
            raise CacheUnavailableError from exc
```

### `src/my_service/cache/cache_aside.py`

```python
import random
from collections.abc import Awaitable, Callable

import structlog
from pydantic import BaseModel, ValidationError

from my_service.cache.port import Cache, CacheUnavailableError

logger = structlog.get_logger()
_JITTER = random.SystemRandom()


class CacheAside[T: BaseModel]:
    def __init__(self, cache: Cache, model: type[T], namespace: str, ttl_seconds: int) -> None:
        self._cache = cache
        self._model = model
        self._namespace = namespace
        self._ttl_seconds = ttl_seconds

    async def get_or_load(self, key: str, loader: Callable[[], Awaitable[T]]) -> T:
        cache_key = self._key(key)
        cached = await self._read(cache_key)
        if cached is not None:
            return cached
        value = await loader()
        try:
            await self._cache.set(cache_key, value.model_dump_json().encode(), self._ttl())
        except CacheUnavailableError:
            logger.warning("cache write skipped", namespace=self._namespace)
        return value

    async def invalidate(self, key: str) -> None:
        try:
            await self._cache.delete(self._key(key))
        except CacheUnavailableError:
            logger.warning(
                "cache invalidation failed; entry expires by ttl", namespace=self._namespace
            )

    async def _read(self, cache_key: str) -> T | None:
        try:
            raw = await self._cache.get(cache_key)
        except CacheUnavailableError:
            logger.warning("cache read skipped", namespace=self._namespace)
            return None
        if raw is None:
            return None
        try:
            return self._model.model_validate_json(raw)
        except ValidationError:
            logger.warning("cache entry discarded", namespace=self._namespace)
            return None

    def _key(self, key: str) -> str:
        return f"{self._namespace}:{key}"

    def _ttl(self) -> int:
        return max(1, round(self._ttl_seconds * _JITTER.uniform(0.9, 1.1)))
```

Rules encoded above:
- **Fail open.** A Redis outage costs latency, never availability: reads fall back to the loader, writes and
  invalidations are logged and skipped. The adapter translates `redis` errors into `CacheUnavailableError`, so no
  vendor exception leaves it.
- **TTL on every entry, with jitter** (±10 %), so entries written together do not expire together (stampede). The TTL
  is also the safety net for a missed invalidation.
- **Invalidate after the commit**, never before: deleting first lets a concurrent reader re-cache the old row.
  A reader that loaded the old row just before the commit can still write it after the delete; the TTL bounds that.
- **Cache DTOs, not ORM rows.** Values are `model_dump_json()` of the response model; an entry that no longer
  validates (after a deploy that changed the model) is discarded and reloaded. Put a version in the namespace
  (`order:v1`) and bump it on a breaking change.
- **Never cache a failure** (`OrderNotFoundError` propagates and nothing is stored) and never put PII in keys: the key
  is the opaque id, not an email (`python-security` §7).

## Use cases
### `src/my_service/operations/get_order.py`

```python
from collections.abc import Callable
from uuid import UUID

from my_service.cache.cache_aside import CacheAside
from my_service.models.responses import OrderResponse
from my_service.repositories.unit_of_work import UnitOfWork


class GetOrderOperation:
    def __init__(
        self, uow_factory: Callable[[], UnitOfWork], cache: CacheAside[OrderResponse]
    ) -> None:
        self._uow_factory = uow_factory
        self._cache = cache

    async def execute(self, order_id: UUID) -> OrderResponse:
        return await self._cache.get_or_load(str(order_id), lambda: self._load(order_id))

    async def _load(self, order_id: UUID) -> OrderResponse:
        async with self._uow_factory() as uow:
            order = await uow.orders.get(order_id)
        return OrderResponse(id=order.id, status=order.status, version=order.version)
```

### `src/my_service/operations/pay_order.py`

```python
from collections.abc import Callable
from uuid import UUID

from my_service.cache.cache_aside import CacheAside
from my_service.models.responses import OrderResponse
from my_service.repositories.unit_of_work import UnitOfWork


class PayOrderOperation:
    def __init__(
        self, uow_factory: Callable[[], UnitOfWork], cache: CacheAside[OrderResponse]
    ) -> None:
        self._uow_factory = uow_factory
        self._cache = cache

    async def execute(self, order_id: UUID, expected_version: int) -> OrderResponse:
        async with self._uow_factory() as uow:
            paid = (await uow.orders.get(order_id)).pay()
            version = await uow.orders.save(paid, expected_version=expected_version)
            await uow.commit()
        await self._cache.invalidate(str(order_id))
        return OrderResponse(id=paid.id, status=paid.status, version=version)
```

Build the Redis client once in the lifespan (`Redis.from_url(settings.redis_url, socket_timeout=0.2,
socket_connect_timeout=0.2)`) and `await client.aclose()` on shutdown; short timeouts are what make "fail open" fast.

## Tests
The fakes import as `tests.fakes.cache` and the in-memory repositories as `tests.fakes.in_memory` (`python-unit-tests`
`references/test-support.md`), so `tests/`, `tests/fakes/`, `tests/unit/` and `tests/integration/` each carry an empty
`__init__.py` (`python-unit-tests` Layout); without them pytest fails with `No module named 'tests'` and mypy reports
`Source file found twice`.

Unit (`InMemoryCache` fake with a `down` switch):
### `tests/fakes/cache.py`

```python
from my_service.cache.port import CacheUnavailableError


class InMemoryCache:
    def __init__(self, down: bool = False) -> None:
        self.store: dict[str, bytes] = {}
        self.ttls: dict[str, int] = {}
        self.down = down

    async def get(self, key: str) -> bytes | None:
        self._check()
        return self.store.get(key)

    async def set(self, key: str, value: bytes, ttl_seconds: int) -> None:
        self._check()
        self.store[key] = value
        self.ttls[key] = ttl_seconds

    async def delete(self, key: str) -> None:
        self._check()
        self.store.pop(key, None)

    def _check(self) -> None:
        if self.down:
            raise CacheUnavailableError
```

### `tests/unit/test_cache_aside.py`

```python
from uuid import UUID, uuid4

import pytest

from my_service.cache.cache_aside import CacheAside
from my_service.errors.domain import OrderNotFoundError
from my_service.models.order import Order
from my_service.models.responses import OrderResponse
from my_service.operations.get_order import GetOrderOperation
from my_service.operations.pay_order import PayOrderOperation
from tests.fakes.cache import InMemoryCache
from tests.fakes.in_memory import InMemoryOrderRepository, InMemoryUnitOfWork


def _aside(cache: InMemoryCache, ttl: int = 60) -> CacheAside[OrderResponse]:
    return CacheAside(cache, OrderResponse, "order:v1", ttl)


class CountingRepository(InMemoryOrderRepository):
    def __init__(self) -> None:
        super().__init__()
        self.reads = 0

    async def get(self, order_id: UUID) -> Order:
        self.reads += 1
        return await super().get(order_id)


async def _seeded() -> tuple[InMemoryOrderRepository, Order]:
    repo = InMemoryOrderRepository()
    order = Order(uuid4(), "c-1", 5, "new")
    await repo.add(order)
    return repo, order


async def test_getOrder_secondRead_isServedFromCacheWithoutTouchingTheDatabase() -> None:
    repo = CountingRepository()
    order = Order(uuid4(), "c-1", 5, "new")
    await repo.add(order)
    cache = InMemoryCache()
    operation = GetOrderOperation(lambda: InMemoryUnitOfWork(repo), _aside(cache))
    first = await operation.execute(order.id)
    second = await operation.execute(order.id)
    assert first == second
    assert repo.reads == 1
    assert f"order:v1:{order.id}" in cache.store


async def test_getOrder_notFound_isNotCached() -> None:
    cache = InMemoryCache()
    operation = GetOrderOperation(
        lambda: InMemoryUnitOfWork(InMemoryOrderRepository()), _aside(cache)
    )
    with pytest.raises(OrderNotFoundError):
        await operation.execute(uuid4())
    assert cache.store == {}


async def test_getOrder_cacheDown_failsOpenToDatabase() -> None:
    repo, order = await _seeded()
    operation = GetOrderOperation(
        lambda: InMemoryUnitOfWork(repo), _aside(InMemoryCache(down=True))
    )
    assert (await operation.execute(order.id)).id == order.id


async def test_getOrder_corruptEntry_isDiscardedAndReloaded() -> None:
    repo, order = await _seeded()
    cache = InMemoryCache()
    cache.store[f"order:v1:{order.id}"] = b"{not json"
    operation = GetOrderOperation(lambda: InMemoryUnitOfWork(repo), _aside(cache))
    assert (await operation.execute(order.id)).status == "new"
    assert b"not json" not in cache.store[f"order:v1:{order.id}"]


async def test_payOrder_invalidatesAfterCommit_soNextReadSeesNewState() -> None:
    repo, order = await _seeded()
    cache = InMemoryCache()
    aside = _aside(cache)
    get = GetOrderOperation(lambda: InMemoryUnitOfWork(repo), aside)
    pay = PayOrderOperation(lambda: InMemoryUnitOfWork(repo), aside)
    await get.execute(order.id)
    repo.rows[order.id] = order.pay()
    await pay.execute(order.id, expected_version=1)
    assert f"order:v1:{order.id}" not in cache.store
    assert (await get.execute(order.id)).status == "paid"


async def test_payOrder_cacheDownDuringInvalidation_stillSucceeds() -> None:
    repo, order = await _seeded()
    pay = PayOrderOperation(lambda: InMemoryUnitOfWork(repo), _aside(InMemoryCache(down=True)))
    assert (await pay.execute(order.id, expected_version=1)).status == "paid"


async def test_ttl_isJitteredAroundConfiguredValue() -> None:
    repo, order = await _seeded()
    cache = InMemoryCache()
    await GetOrderOperation(lambda: InMemoryUnitOfWork(repo), _aside(cache, ttl=100)).execute(
        order.id
    )
    assert 90 <= cache.ttls[f"order:v1:{order.id}"] <= 110
```

Integration against a Redis container, including expiry and an unreachable server:
### `tests/integration/test_redis_cache.py`

```python
import asyncio
from collections.abc import AsyncIterator, Iterator
from uuid import uuid4

import docker
import pytest
from pydantic import BaseModel
from redis.asyncio import Redis
from testcontainers.community.redis import RedisContainer

from my_service.cache.cache_aside import CacheAside
from my_service.cache.port import CacheUnavailableError
from my_service.cache.redis_cache import RedisCache


class Thing(BaseModel):
    name: str


@pytest.fixture(scope="session")
def redis_url() -> Iterator[str]:
    try:
        docker.from_env().ping()
    except docker.errors.DockerException:
        pytest.skip("Docker is not available: integration tests skipped")
    with RedisContainer("redis:7-alpine") as redis:
        yield f"redis://{redis.get_container_host_ip()}:{redis.get_exposed_port(6379)}"


@pytest.fixture
async def cache(redis_url: str) -> AsyncIterator[RedisCache]:
    client = Redis.from_url(redis_url)
    yield RedisCache(client)
    await client.aclose()


async def test_redisCache_setGetDelete_roundTrips(cache: RedisCache) -> None:
    key = f"k:{uuid4()}"
    assert await cache.get(key) is None
    await cache.set(key, b"v", ttl_seconds=30)
    assert await cache.get(key) == b"v"
    await cache.delete(key)
    assert await cache.get(key) is None


async def test_redisCache_entryExpiresAfterTtl(cache: RedisCache) -> None:
    key = f"k:{uuid4()}"
    await cache.set(key, b"v", ttl_seconds=1)
    async with asyncio.timeout(5):
        while await cache.get(key) is not None:  # noqa: ASYNC110 - polling an external TTL
            await asyncio.sleep(0.1)


async def test_cacheAside_loadsOnceThenServesFromRedisUntilInvalidated(
    cache: RedisCache,
) -> None:
    aside = CacheAside(cache, Thing, f"thing:{uuid4()}", ttl_seconds=60)
    loads: list[int] = []

    async def loader() -> Thing:
        loads.append(1)
        return Thing(name=f"v{len(loads)}")

    assert (await aside.get_or_load("a", loader)).name == "v1"
    assert (await aside.get_or_load("a", loader)).name == "v1"
    await aside.invalidate("a")
    assert (await aside.get_or_load("a", loader)).name == "v2"
    assert len(loads) == 2


async def test_redisCache_serverUnreachable_raisesCacheUnavailable() -> None:
    client = Redis.from_url("redis://127.0.0.1:1", socket_connect_timeout=0.5)
    with pytest.raises(CacheUnavailableError):
        await RedisCache(client).get("k")
    await client.aclose()


async def test_cacheAside_redisDown_failsOpenToLoader() -> None:
    client = Redis.from_url("redis://127.0.0.1:1", socket_connect_timeout=0.5)
    aside = CacheAside(RedisCache(client), Thing, "thing", ttl_seconds=60)

    async def loader() -> Thing:
        return Thing(name="from-db")

    assert (await aside.get_or_load("a", loader)).name == "from-db"
    await client.aclose()
```


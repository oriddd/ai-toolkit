# python-fastapi-conventions — composition root, providers and routers

Back to [`SKILL.md`](../SKILL.md) §1, §2 and §7. The complete application factory, the `Depends` providers and the
two routers of the sample service. `create_app(settings)` takes explicit settings (tests) or reads the environment
(production); the lifespan owns the engine, the Redis client and the billing HTTP client on one `AsyncExitStack`,
so they close in reverse order. The outbox relay runs in the worker process (`python-messaging`), not here.

## Application factory

### `src/my_service/main.py`

```python
from collections.abc import AsyncIterator
from contextlib import AsyncExitStack, asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import make_asgi_app
from redis.asyncio import Redis
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from my_service.api.errors import register_exception_handlers
from my_service.api.routers import health, orders
from my_service.cache.cache_aside import CacheAside
from my_service.cache.redis_cache import RedisCache
from my_service.clients.billing.http_billing_client import HttpBillingClient
from my_service.clients.billing.retry import RetryPolicy
from my_service.clients.billing.transport import build_billing_http_client
from my_service.clients.circuit_breaker import CircuitBreaker
from my_service.config.settings import AppSettings
from my_service.models.responses import OrderResponse
from my_service.observability.correlation import CorrelationIdMiddleware
from my_service.observability.logging import configure_logging
from my_service.observability.metrics import MetricsMiddleware
from my_service.observability.tracing import configure_tracing
from my_service.security.token_verifier import JwksKeySource, JwtTokenVerifier


def create_app(settings: AppSettings | None = None) -> FastAPI:
    resolved = settings or AppSettings()
    configure_logging()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        async with AsyncExitStack() as stack:
            engine = create_async_engine(
                resolved.db.sqlalchemy_url(), pool_size=resolved.db.pool_size
            )
            stack.push_async_callback(engine.dispose)
            redis = Redis.from_url(
                resolved.redis_url, socket_timeout=0.2, socket_connect_timeout=0.2
            )
            stack.push_async_callback(redis.aclose)
            billing_http = await stack.enter_async_context(
                build_billing_http_client(resolved.billing)
            )
            app.state.engine = engine
            app.state.session_factory = async_sessionmaker(engine, expire_on_commit=False)
            app.state.order_cache = CacheAside(RedisCache(redis), OrderResponse, "order:v1", 60)
            app.state.billing = HttpBillingClient(
                billing_http,
                RetryPolicy(max_attempts=resolved.billing.attempts),
                CircuitBreaker("billing"),
            )
            app.state.token_verifier = JwtTokenVerifier(
                JwksKeySource(resolved.auth.jwks_url), resolved.auth.issuer, resolved.auth.audience
            )
            yield

    app = FastAPI(
        title="my-service",
        lifespan=lifespan,
        docs_url="/docs" if resolved.expose_docs else None,
        redoc_url=None,
        openapi_url="/openapi.json" if resolved.expose_docs else None,
    )
    register_exception_handlers(app)
    app.add_middleware(MetricsMiddleware)
    if resolved.cors_origins:
        app.add_middleware(CORSMiddleware, allow_origins=resolved.cors_origins)
    app.add_middleware(CorrelationIdMiddleware)
    app.mount("/metrics", make_asgi_app())
    app.include_router(health.router)
    app.include_router(orders.router)
    if resolved.otlp_endpoint:
        configure_tracing("my-service", resolved.otlp_endpoint, app)
    return app
```

## Providers

### `src/my_service/api/dependencies.py`

```python
from collections.abc import Callable
from functools import partial
from typing import Annotated

from fastapi import Depends, Request
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from my_service.cache.cache_aside import CacheAside
from my_service.clients.billing.port import BillingGateway
from my_service.models.responses import OrderResponse
from my_service.operations.create_order import CreateOrderOperation
from my_service.operations.get_order import GetOrderOperation
from my_service.operations.pay_order import PayOrderOperation
from my_service.repositories.unit_of_work import SqlUnitOfWork, UnitOfWork
from my_service.security.token_verifier import TokenVerifier
from my_service.services.clock import SystemClock
from my_service.services.ids import RandomIds
from my_service.validation.rules import SufficientCreditRule


def get_engine(request: Request) -> AsyncEngine:
    engine: AsyncEngine = request.app.state.engine
    return engine


def get_uow_factory(request: Request) -> Callable[[], UnitOfWork]:
    factory: async_sessionmaker[AsyncSession] = request.app.state.session_factory
    return partial(SqlUnitOfWork, factory)


def get_token_verifier(request: Request) -> TokenVerifier:
    verifier: TokenVerifier = request.app.state.token_verifier
    return verifier


def get_billing_gateway(request: Request) -> BillingGateway:
    billing: BillingGateway = request.app.state.billing
    return billing


def get_order_cache(request: Request) -> CacheAside[OrderResponse]:
    cache: CacheAside[OrderResponse] = request.app.state.order_cache
    return cache


def get_get_order_operation(
    uow_factory: Annotated[Callable[[], UnitOfWork], Depends(get_uow_factory)],
    cache: Annotated[CacheAside[OrderResponse], Depends(get_order_cache)],
) -> GetOrderOperation:
    return GetOrderOperation(uow_factory, cache)


def get_pay_order_operation(
    uow_factory: Annotated[Callable[[], UnitOfWork], Depends(get_uow_factory)],
    cache: Annotated[CacheAside[OrderResponse], Depends(get_order_cache)],
) -> PayOrderOperation:
    return PayOrderOperation(uow_factory, cache)


def get_create_order_operation(
    uow_factory: Annotated[Callable[[], UnitOfWork], Depends(get_uow_factory)],
    billing: Annotated[BillingGateway, Depends(get_billing_gateway)],
) -> CreateOrderOperation:
    return CreateOrderOperation(
        uow_factory, SystemClock(), RandomIds(), [SufficientCreditRule(billing)]
    )
```

## Routers

### `src/my_service/api/routers/orders.py`

```python
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Response, status

from my_service.api.dependencies import (
    get_create_order_operation,
    get_get_order_operation,
    get_pay_order_operation,
)
from my_service.api.security import OrdersReader, OrdersWriter
from my_service.models.requests import CreateOrderRequest, PayOrderRequest
from my_service.models.responses import OrderResponse
from my_service.operations.create_order import CreateOrderOperation
from my_service.operations.get_order import GetOrderOperation
from my_service.operations.pay_order import PayOrderOperation

router = APIRouter(prefix="/v1/orders", tags=["orders"])


@router.post("", status_code=status.HTTP_201_CREATED, response_model=OrderResponse)
async def create_order(
    body: CreateOrderRequest,
    operation: Annotated[CreateOrderOperation, Depends(get_create_order_operation)],
    response: Response,
    caller: OrdersWriter,
) -> OrderResponse:
    created = await operation.execute(body)
    response.headers["Location"] = f"{router.prefix}/{created.id}"
    return created


@router.get("/{order_id}", response_model=OrderResponse)
async def get_order(
    order_id: UUID,
    operation: Annotated[GetOrderOperation, Depends(get_get_order_operation)],
    caller: OrdersReader,
) -> OrderResponse:
    return await operation.execute(order_id)


@router.post("/{order_id}/pay", response_model=OrderResponse)
async def pay_order(
    order_id: UUID,
    body: PayOrderRequest,
    operation: Annotated[PayOrderOperation, Depends(get_pay_order_operation)],
    caller: OrdersWriter,
) -> OrderResponse:
    return await operation.execute(order_id, body.version)
```

### `src/my_service/api/routers/health.py`

```python
import asyncio
from typing import Annotated

from fastapi import APIRouter, Depends, Response, status
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine

from my_service.api.dependencies import get_engine

router = APIRouter(prefix="/health", tags=["health"])


@router.get("/live")
async def live() -> dict[str, str]:
    return {"status": "UP"}


@router.get("/ready")
async def ready(
    engine: Annotated[AsyncEngine, Depends(get_engine)], response: Response
) -> dict[str, str]:
    try:
        async with asyncio.timeout(2), engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
    except Exception:  # noqa: BLE001 - readiness reports any failure as DOWN
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "DOWN"}
    return {"status": "UP"}
```

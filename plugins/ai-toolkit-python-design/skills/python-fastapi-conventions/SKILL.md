---
name: python-fastapi-conventions
description: >
  Python FastAPI conventions — thin routers, Depends injection, explicit response models, one pagination contract,
  problem+json errors, lifespan-managed resources. Use when adding or changing an endpoint, router, dependency or app
  factory. Layout lives in `python-code-structure`.
tier: must
applies_to: [rest]
depends_on: [python-code-structure]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# Python FastAPI Conventions Skill
## When to use
Whenever you add or change an HTTP endpoint, a router, a `Depends` provider or the application factory.

## Layout

```
src/my_service/
├── main.py                    # create_app(), lifespan, router registration
└── api/
    ├── dependencies.py        # Depends providers (the only place that builds the object graph per request)
    ├── errors.py              # exception handlers (see `python-error-handling`)
    └── routers/
        ├── orders.py          # one router per resource
        └── health.py
```

## Dependencies
```toml
dependencies = ["fastapi>=0.115", "uvicorn[standard]>=0.30", "pydantic>=2.8", "pydantic-settings>=2.4"]
```

## 1. Thin routers
A route function parses input (already validated by its model), calls **one** operation/service and
returns a response model. No business rules, no `try/except` for domain errors, no DB sessions.

```python
router = APIRouter(prefix="/v1/orders", tags=["orders"])

@router.post("", status_code=status.HTTP_201_CREATED, response_model=OrderResponse)
async def create_order(
    body: CreateOrderRequest,
    operation: Annotated[CreateOrderOperation, Depends(get_create_order_operation)],
    response: Response,
) -> OrderResponse:
    created = await operation.execute(body)
    response.headers["Location"] = f"{router.prefix}/{created.id}"   # 201 always carries Location
    return created
```

## 2. Dependencies are the injection seam
Providers live in `api/dependencies.py`, are typed with `Annotated`, and return `Protocol`-typed
collaborators. Singletons (engine, session factory, HTTP clients) come from `request.app.state`, set in the
lifespan; per-request objects (unit of work, current user) are built here. Never share one session
across requests. Tests swap providers with `app.dependency_overrides`.

```python
def get_uow_factory(request: Request) -> Callable[[], UnitOfWork]:
    factory: async_sessionmaker[AsyncSession] = request.app.state.session_factory
    return partial(SqlUnitOfWork, factory)          # `python-persistence`: a new session per unit of work

def get_create_order_operation(
    uow_factory: Annotated[Callable[[], UnitOfWork], Depends(get_uow_factory)],
) -> CreateOrderOperation:
    return CreateOrderOperation(uow_factory)        # the operation opens `async with uow_factory() as uow`
```

The provider is typed with the `UnitOfWork` Protocol (from `python-persistence`), so a test override can
return an in-memory fake. **One transaction owner:** the use case the router calls opens the unit of work,
which is the `*Operation`, or the `*Service` when the use case needs no operation (`python-code-structure` §7).
Services called by an operation receive the open unit of work's repositories; they never open a second one.

## 3. Explicit response models
Every route declares `response_model` (or a return annotation) with a pydantic model separate from
the persistence model; never return ORM objects or `dict`. Use `response_model_exclude_none=True` only
deliberately. Declare error statuses in `responses={404: {"model": ProblemDetail}}`.

## 4. Pagination contract
One shape for every collection endpoint: `GET /v1/orders?limit=50&cursor=...` (or `page`/`size` if
offset paging is justified). Limits are bounded; the maximum is enforced, not trusted.

```python
class Page[T](BaseModel):
    items: list[T]
    next_cursor: str | None = None
    total: int | None = None

class PageParams(BaseModel):
    limit: int = Field(default=50, ge=1, le=200)
    cursor: str | None = None

@router.get("", response_model=Page[OrderResponse])
async def list_orders(
    customer_id: str,
    page: Annotated[PageParams, Query()],    # without Query() a model parameter is read from the request body
    operation: Annotated[ListOrdersOperation, Depends(get_list_orders_operation)],
) -> Page[OrderResponse]:
    return await operation.execute(customer_id, page)
```

## 5. Errors are problem+json
Every non-2xx body is RFC 9457 `application/problem+json` produced by the handlers registered by
`python-error-handling` (domain errors, validation, framework 404/405 and the catch-all 500). Routers never build error responses by hand and never raise `HTTPException`.

## 6. URL conventions
- Plural, lowercase, kebab-case nouns: `/v1/purchase-orders/{order_id}`; no verbs in paths.
- Version in the path prefix (`/v1`); breaking change means `/v2`, never a silent change.
- Verbs: `GET` safe, `PUT` full replace (idempotent), `PATCH` partial, `DELETE` idempotent, `POST` create (201 + `Location`).
- Sub-resources at most two levels deep; filters are query parameters.
- Long work returns `202 Accepted` with a status resource.

## 7. Lifespan, not startup events
Create and close shared resources (DB engine, HTTP clients) in one `lifespan`, attach to `app.state`.
The session *factory* is the shared object; sessions and units of work are created per request (section 2).

```python
def create_app(settings: AppSettings | None = None) -> FastAPI:
    resolved = settings or AppSettings()        # production reads the environment; tests pass settings

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        engine = create_async_engine(resolved.db.sqlalchemy_url(), pool_size=resolved.db.pool_size)
        app.state.session_factory = async_sessionmaker(engine, expire_on_commit=False)
        yield
        await engine.dispose()

    app = FastAPI(title="my-service", lifespan=lifespan)
    register_exception_handlers(app)
    app.add_middleware(MetricsMiddleware)           # `python-observability` §4
    app.add_middleware(CorrelationIdMiddleware)     # added last = outermost: every log line has the ID
    app.mount("/metrics", make_asgi_app())          # prometheus-client; keep it off the public ingress
    app.include_router(health.router)               # /health/live and /health/ready
    app.include_router(orders.router)
    return app
```

`create_app()` is a factory so tests build isolated apps: unit tests pass explicit settings
(`create_app(test_settings)`, no `DB_*` environment needed; the engine connects lazily, so with the
unit-of-work provider overridden nothing touches a database). Tests must run the lifespan
(`with TestClient(app)` or `asgi-lifespan`, see `python-unit-tests`), otherwise `app.state` is empty. Add `/health/live` and `/health/ready`.

## Do / Don't
- ✅ `async def` routes only when everything awaited inside is async; otherwise `def` (runs in the threadpool).
- ✅ Separate request, response and persistence models.
- ✅ Use `Annotated[..., Depends(...)]`; override dependencies in tests.
- ❌ `@app.on_event`, global `app = FastAPI()` with side effects at import time.
- ❌ Blocking calls (`requests`, sync DB driver) inside `async def`.
- ❌ `HTTPException` in services, or returning `JSONResponse` error dicts from routes.
- ❌ Unbounded list endpoints.

## Cross-references
- `python-code-structure` — where routers sit and what they may import.
- `python-error-handling` — the exception-to-problem+json mapping.
- `python-input-validation` — request models and rule objects.
- `python-observability` — request logging, metrics and tracing middleware.

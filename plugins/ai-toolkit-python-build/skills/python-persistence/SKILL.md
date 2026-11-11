---
name: python-persistence
description: >
  Python persistence with SQLAlchemy 2.0 (typed models, async sessions) and Alembic — repository per aggregate behind
  a Protocol, one unit-of-work boundary, optimistic locking. Use when adding storage, an entity, a migration or a
  query.
tier: should
applies_to: [rest, worker]
depends_on: [python-code-structure, python-error-handling]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# Python Persistence Skill
## When to use
Whenever a service reads or writes a relational database, adds an entity, or changes the schema.

## Layout

```
src/my_service/
├── models/order.py                  # pure domain/pydantic Order (no SQLAlchemy)
├── repositories/
│   ├── order_repository.py          # Protocol: the port
│   ├── sql_order_repository.py      # SQLAlchemy adapter
│   ├── orm.py                       # Mapped classes (private to this package)
│   └── unit_of_work.py              # transaction boundary
└── alembic/versions/                # migrations
alembic.ini                          # repo root; points at src/my_service/alembic
```

`alembic.ini` stays at the repository root with `script_location = %(here)s/src/my_service/alembic`, so the
CLI, CI and the integration tests (which load `Config("alembic.ini")`) all run from the root.

## Dependencies
```toml
dependencies = ["sqlalchemy[asyncio]>=2.0.30", "asyncpg>=0.29", "alembic>=1.13"]
```

## 1. Typed ORM models, private to the package
```python
class Base(DeclarativeBase): ...

class OrderRow(Base):
    __tablename__ = "orders"

    id: Mapped[UUID] = mapped_column(primary_key=True)
    customer_id: Mapped[str] = mapped_column(String(64), index=True)
    total_cents: Mapped[int]
    status: Mapped[str] = mapped_column(String(16))
    version: Mapped[int] = mapped_column(default=1)
    __mapper_args__ = {"version_id_col": version}  # noqa: RUF012 - ClassVar here breaks mypy
```

## 2. Repository behind a Protocol, domain objects in and out
One repository per aggregate, one method per access shape, no generic `query(**filters)`.

```python
class OrderRepository(Protocol):
    async def get(self, order_id: UUID) -> Order: ...        # raises OrderNotFoundError
    async def add(self, order: Order) -> None: ...     # INSERT; raises OrderAlreadyExistsError
    # UPDATE; returns the NEW version; raises OrderVersionConflictError
    async def save(self, order: Order, expected_version: int) -> int: ...
    async def list_by_customer(self, customer_id: str, limit: int) -> list[Order]: ...

class SqlOrderRepository:
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def get(self, order_id: UUID) -> Order:
        row = await self._session.get(OrderRow, order_id)
        if row is None:
            raise OrderNotFoundError(order_id=order_id)
        return _to_domain(row)

    async def add(self, order: Order) -> None:
        self._session.add(_to_row(order))
        try:
            await self._session.flush()
        except IntegrityError as exc:            # duplicate id or another unique constraint
            raise OrderAlreadyExistsError(order_id=order.id) from exc

    async def save(self, order: Order, expected_version: int) -> int:
        row = await self._session.get(OrderRow, order.id)
        if row is None:
            raise OrderNotFoundError(order_id=order.id)
        set_committed_value(row, "version", expected_version)  # WHERE version = expected
        row.customer_id = order.customer_id
        row.total_cents = order.total_cents
        row.status = order.status
        flag_modified(row, "status")   # force the UPDATE and version bump even if nothing changed
        try:
            await self._session.flush()
        except StaleDataError as exc:
            raise OrderVersionConflictError(order_id=order.id) from exc
        return row.version             # the version after the flush: hand it back to the client
```

`add` is for new aggregates only: calling it for an existing id re-INSERTs, and the `IntegrityError` becomes
`OrderAlreadyExistsError` (a `ConflictError`, 409, catalogued in `python-error-handling`). Changes to existing ones go through `save`. `_to_domain` / `_to_row` live next to the adapter. Services and routers never see `OrderRow`,
`Session` or SQLAlchemy exceptions.

## 3. Transaction boundary: one unit of work per use case
The use case the router calls opens the transaction: the operation, or the service when there is no
operation (see `python-fastapi-conventions` §2). Repositories never commit. Use cases depend on the
`UnitOfWork` Protocol, so unit tests pass an in-memory fake (see `python-unit-tests` §3):

```python
class UnitOfWork(Protocol):
    orders: OrderRepository

    async def __aenter__(self) -> Self: ...
    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None: ...
    async def commit(self) -> None: ...

class SqlUnitOfWork:
    def __init__(self, factory: async_sessionmaker[AsyncSession]) -> None:
        self._factory = factory

    async def __aenter__(self) -> Self:
        self._session = self._factory()
        self.orders: OrderRepository = SqlOrderRepository(self._session)
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        tb: TracebackType | None,
    ) -> None:
        if exc_type is not None:
            await self._session.rollback()
        await self._session.close()

    async def commit(self) -> None:
        try:
            await self._session.commit()
        except StaleDataError as exc:
            raise OrderVersionConflictError() from exc  # no order_id here: tolerated
        except IntegrityError as exc:  # an autoflushed duplicate surfaces at commit
            raise OrderAlreadyExistsError() from exc
```

Build the factory once in the lifespan with `expire_on_commit=False` (attributes stay readable after
commit, no implicit lazy load in async code):
`factory = async_sessionmaker(engine, expire_on_commit=False)`.

```python
# expected_version comes from the CLIENT (If-Match header or body field), never from the row
# just read: order.version would always match, so a stale client would silently overwrite.
async with uow_factory() as uow:
    paid = (await uow.orders.get(order_id)).pay()
    new_version = await uow.orders.save(paid, expected_version=request.version)
    await uow.commit()
return OrderResponse(id=paid.id, status=paid.status, version=new_version)  # client sends it back
```

## 4. Optimistic locking
The `version_id_col` above makes a stale update raise `StaleDataError` **at flush/commit time**, not
when the attribute is set. `save` therefore pins the caller's `expected_version` as the committed
version (`set_committed_value`), so the `UPDATE ... WHERE version = expected` matches zero rows when
someone else won, and translates the error where the flush happens (inside `save`, and in
`commit()` for autoflushed changes), keeping the cause: `raise OrderVersionConflictError(order_id=...)
from exc` (a `ConflictError`, mapped to 409 by `python-error-handling`). `DomainError` formats its message tolerantly (a missing placeholder renders as `<unknown>`, see `python-error-handling`), so the commit-time raise carries no params instead of failing with `KeyError`.
Expose `version` in responses and accept it back (`If-Match`/field): `save` returns the post-flush version, so the domain object the caller holds
never goes stale after its own write. Pitfall: SQLAlchemy emits no `UPDATE` when no column changed, so a stale `save` of identical data
would silently succeed and not bump the version; `flag_modified(row, "status")` guarantees the `UPDATE ... WHERE version = expected`
(without it, a second identical PUT keeps the version and a stale PUT returns no conflict).
Translate `IntegrityError` for unique constraints into a typed domain error the same way (`add` and `commit` above).

## 5. Migrations with Alembic
Schema changes only via migrations; never `Base.metadata.create_all` outside tests.
`alembic revision --autogenerate -m "add orders"`, then **review** the generated script. Migrations are
forward-compatible (add nullable column -> backfill -> enforce) so old and new app versions overlap on deploy.
The integration suite runs `upgrade head` on an empty database (its `engine` fixture) and `alembic check`
for drift (a test, see `python-integration-tests` §3), so the CI integration job covers both.

Generated scripts must pass the same lint gate as the code. Let Alembic run ruff on every new revision
(uncomment and adapt the `[post_write_hooks]` section of `alembic.ini`):

```ini
[post_write_hooks]
hooks = ruff_fix, ruff_format
ruff_fix.type = exec
ruff_fix.executable = %(here)s/.venv/bin/ruff
ruff_fix.options = check --fix REVISION_SCRIPT_FILENAME
ruff_format.type = exec
ruff_format.executable = %(here)s/.venv/bin/ruff
ruff_format.options = format REVISION_SCRIPT_FILENAME
```

## 6. Querying rules
- Always bound lists (`limit`); paginate by keyset for large tables.
- Avoid N+1: `selectinload` / `joinedload` chosen explicitly in the repository method that needs them.
- Use `select()` statements; no raw SQL strings with interpolation (parameters only).

## Do / Don't
- ✅ Map ORM rows to domain objects inside the repository.
- ✅ Commit only in the operation/unit of work; repositories only `add`/`get`/`save`.
- ✅ Test the SQL adapter against a real database (see `python-integration-tests`); test services with an in-memory fake repository.
- ❌ Returning `OrderRow` or `Result` objects from a repository.
- ❌ `session.commit()` inside a repository, or sessions stored in globals.
- ❌ Lazy loading across the async boundary (`MissingGreenlet`); relationships accessed after the session closes.
- ❌ Editing an applied migration; use a new one.

## Cross-references
- `python-code-structure` — repositories as an injected port.
- `python-error-handling` — `NotFound`/`Conflict` errors raised from the adapter.
- `python-integration-tests` — real-database tests and Alembic checks.
- `python-unit-tests` — in-memory fake repositories.

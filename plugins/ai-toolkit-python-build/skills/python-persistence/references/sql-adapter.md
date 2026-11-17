# python-persistence — ORM, repository, unit of work and Alembic

Back to [`SKILL.md`](../SKILL.md) §1 to §5. `orm.py` holds every table of the service: `OutboxRow` and
`ProcessedMessageRow` belong to `python-messaging` (§2 and §4), so delete them and their imports in a service without
messaging. `UnitOfWork.outbox` likewise exists only with messaging; the in-memory fake in `python-unit-tests` mirrors it.

After `uv run alembic init -t async src/my_service/alembic`, set `script_location = my_service:alembic`, replace the
commented `[post_write_hooks]` section of `alembic.ini` with the block below, overwrite the generated `env.py` with the
one below, then run `uv run alembic revision --autogenerate -m "initial schema"` against an empty database. The
post-write hook formats the revision, so it passes `ruff check` and `ruff format --check` unchanged.

## ORM rows

### `src/my_service/repositories/orm.py`

```python
from datetime import datetime
from uuid import UUID

from sqlalchemy import DateTime, Index, String, func, text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase): ...


class OrderRow(Base):
    __tablename__ = "orders"
    id: Mapped[UUID] = mapped_column(primary_key=True)
    customer_id: Mapped[str] = mapped_column(String(64), index=True)
    total_cents: Mapped[int]
    status: Mapped[str] = mapped_column(String(16))
    version: Mapped[int] = mapped_column(default=1)
    __mapper_args__ = {"version_id_col": version}  # noqa: RUF012 - ClassVar here breaks mypy


class OutboxRow(Base):
    __tablename__ = "outbox"
    id: Mapped[UUID] = mapped_column(primary_key=True)
    topic: Mapped[str] = mapped_column(String(128))
    key: Mapped[str] = mapped_column(String(128))
    event_type: Mapped[str] = mapped_column(String(64))
    payload: Mapped[dict[str, object]] = mapped_column(JSONB)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    __table_args__ = (
        Index("ix_outbox_unpublished", "created_at", postgresql_where=text("published_at IS NULL")),
    )


class ProcessedMessageRow(Base):
    __tablename__ = "processed_message"
    consumer: Mapped[str] = mapped_column(String(128), primary_key=True)
    message_id: Mapped[UUID] = mapped_column(primary_key=True)
    processed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
```

## Repository and unit of work

### `src/my_service/repositories/order_repository.py`

```python
from typing import Protocol
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm.attributes import flag_modified, set_committed_value
from sqlalchemy.orm.exc import StaleDataError

from my_service.errors.domain import (
    OrderAlreadyExistsError,
    OrderNotFoundError,
    OrderVersionConflictError,
)
from my_service.models.order import Order
from my_service.repositories.orm import OrderRow


class OrderRepository(Protocol):
    async def get(self, order_id: UUID) -> Order: ...
    async def add(self, order: Order) -> None: ...
    async def save(self, order: Order, expected_version: int) -> int: ...
    async def list_by_customer(self, customer_id: str, limit: int) -> list[Order]: ...


def _to_domain(row: OrderRow) -> Order:
    return Order(row.id, row.customer_id, row.total_cents, row.status, row.version)


def _to_row(order: Order) -> OrderRow:
    return OrderRow(
        id=order.id,
        customer_id=order.customer_id,
        total_cents=order.total_cents,
        status=order.status,
        version=order.version,
    )


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
        except IntegrityError as exc:
            raise OrderAlreadyExistsError(order_id=order.id) from exc

    async def save(self, order: Order, expected_version: int) -> int:
        row = await self._session.get(OrderRow, order.id)
        if row is None:
            raise OrderNotFoundError(order_id=order.id)
        set_committed_value(row, "version", expected_version)
        row.customer_id = order.customer_id
        row.total_cents = order.total_cents
        row.status = order.status
        flag_modified(row, "status")
        try:
            await self._session.flush()
        except StaleDataError as exc:
            raise OrderVersionConflictError(order_id=order.id) from exc
        return row.version

    async def list_by_customer(self, customer_id: str, limit: int) -> list[Order]:
        rows = await self._session.scalars(
            select(OrderRow).where(OrderRow.customer_id == customer_id).limit(limit)
        )
        return [_to_domain(r) for r in rows]
```

### `src/my_service/repositories/unit_of_work.py`

```python
from types import TracebackType
from typing import Protocol, Self

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.orm.exc import StaleDataError

from my_service.errors.domain import OrderAlreadyExistsError, OrderVersionConflictError
from my_service.repositories.order_repository import OrderRepository, SqlOrderRepository
from my_service.repositories.outbox import Outbox, SqlOutbox


class UnitOfWork(Protocol):
    orders: OrderRepository
    outbox: Outbox

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
        self.outbox: Outbox = SqlOutbox(self._session)
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
            raise OrderVersionConflictError() from exc
        except IntegrityError as exc:
            raise OrderAlreadyExistsError() from exc
```

## Alembic

### `alembic.ini#post_write_hooks`

```ini
[post_write_hooks]
hooks = ruff_fix, ruff_format
ruff_fix.type = module
ruff_fix.module = ruff
ruff_fix.options = check --fix REVISION_SCRIPT_FILENAME
ruff_format.type = module
ruff_format.module = ruff
ruff_format.options = format REVISION_SCRIPT_FILENAME
```

### `src/my_service/alembic/env.py`

```python
import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from my_service.config.settings import DatabaseSettings
from my_service.repositories.orm import Base

# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

# Interpret the config file for Python logging.
# This line sets up loggers basically.
if config.attributes.get("connection") is None:
    if config.config_file_name is not None:
        fileConfig(config.config_file_name)
    url = DatabaseSettings().sqlalchemy_url().render_as_string(hide_password=False)
    config.set_main_option("sqlalchemy.url", url.replace("%", "%%"))

# add your model's MetaData object here
# for 'autogenerate' support
# from myapp import mymodel
# target_metadata = mymodel.Base.metadata
target_metadata = Base.metadata

# other values from the config, defined by the needs of env.py,
# can be acquired:
# my_important_option = config.get_main_option("my_important_option")
# ... etc.


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode.

    This configures the context with just a URL
    and not an Engine, though an Engine is acceptable
    here as well.  By skipping the Engine creation
    we don't even need a DBAPI to be available.

    Calls to context.execute() here emit the given string to the
    script output.

    """
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata)

    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    """In this scenario we need to create an Engine
    and associate a connection with the context.

    """

    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)

    await connectable.dispose()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode."""

    connection = config.attributes.get("connection")
    if connection is not None:
        do_run_migrations(connection)
        return
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
```

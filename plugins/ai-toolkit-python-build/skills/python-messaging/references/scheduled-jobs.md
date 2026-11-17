# python-messaging — scheduled jobs and retention

Back to [`SKILL.md`](../SKILL.md) §7. Periodic work runs as a Kubernetes `CronJob` (`python-cd` §7) that executes
`my-service-job <name>` from the service image. Add `my-service-job = "my_service.jobs:main"` under
`[project.scripts]`. Tested against PostgreSQL (testcontainers) and on a kind cluster.

## Single-run guarantee: a session-level advisory lock
### `src/my_service/repositories/exclusive.py`

```python
from collections.abc import Awaitable, Callable

import structlog
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncEngine

logger = structlog.get_logger()


async def run_exclusive(
    engine: AsyncEngine, lock_key: int, job: Callable[[], Awaitable[object]]
) -> bool:
    async with engine.connect() as conn:
        if not await conn.scalar(select(func.pg_try_advisory_lock(lock_key))):
            logger.info("job skipped: another instance holds the lock", lock_key=lock_key)
            return False
        try:
            await job()
        finally:
            await conn.scalar(select(func.pg_advisory_unlock(lock_key)))
    return True
```

`pg_try_advisory_lock` is bound to the connection, so `run_exclusive` holds one connection for the whole job and
releases the lock in `finally`; if the process dies, PostgreSQL drops the lock with the connection. It does not work
through PgBouncer in transaction-pooling mode (the lock would belong to whichever server connection served the
statement): give jobs a direct connection. Give every job its own key; relay and consumer keys must differ.

## Retention: batched, skip-locked deletes
### `src/my_service/repositories/retention.py`

```python
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.sql.dml import ReturningDelete

from my_service.repositories.orm import OutboxRow, ProcessedMessageRow


class SqlRetention:
    def __init__(self, factory: async_sessionmaker[AsyncSession], batch_size: int = 1000) -> None:
        self._factory = factory
        self._batch_size = batch_size

    async def purge_published_outbox(self, older_than: timedelta) -> int:
        cutoff = datetime.now(UTC) - older_than
        return await self._purge_in_batches(
            lambda: (
                delete(OutboxRow)
                .where(
                    OutboxRow.id.in_(
                        select(OutboxRow.id)
                        .where(OutboxRow.published_at < cutoff)
                        .limit(self._batch_size)
                        .with_for_update(skip_locked=True)
                    )
                )
                .returning(OutboxRow.id)
            )
        )

    async def purge_processed_messages(self, older_than: timedelta) -> int:
        cutoff = datetime.now(UTC) - older_than
        return await self._purge_in_batches(
            lambda: (
                delete(ProcessedMessageRow)
                .where(
                    ProcessedMessageRow.message_id.in_(
                        select(ProcessedMessageRow.message_id)
                        .where(ProcessedMessageRow.processed_at < cutoff)
                        .limit(self._batch_size)
                        .with_for_update(skip_locked=True)
                    )
                )
                .returning(ProcessedMessageRow.message_id)
            )
        )

    async def _purge_in_batches(self, batch: Callable[[], ReturningDelete[Any]]) -> int:
        total = 0
        while True:
            async with self._factory() as session, session.begin():
                deleted = len((await session.execute(batch())).all())
            total += deleted
            if deleted < self._batch_size:
                return total
```

Each batch is its own short transaction, so a large purge neither holds locks for long nor loses all progress when
it is killed, and `FOR UPDATE SKIP LOCKED` leaves rows the relay is publishing alone. The same shape serves PII
retention (`python-security` §7): one `purge_*` method per table and retention period.

## Registry and entrypoint
### `src/my_service/jobs.py`

```python
import argparse
import asyncio
from collections.abc import Awaitable, Callable
from datetime import timedelta

import structlog
from sqlalchemy.ext.asyncio import AsyncEngine, async_sessionmaker, create_async_engine

from my_service.config.settings import AppSettings
from my_service.observability.logging import configure_logging
from my_service.repositories.exclusive import run_exclusive
from my_service.repositories.retention import SqlRetention

logger = structlog.get_logger()

OUTBOX_RETENTION = timedelta(days=7)
PROCESSED_RETENTION = timedelta(days=30)

JobFactory = Callable[[AsyncEngine], Callable[[], Awaitable[object]]]


def _purge_outbox(engine: AsyncEngine) -> Callable[[], Awaitable[object]]:
    retention = SqlRetention(async_sessionmaker(engine))
    return lambda: retention.purge_published_outbox(OUTBOX_RETENTION)


def _purge_processed(engine: AsyncEngine) -> Callable[[], Awaitable[object]]:
    retention = SqlRetention(async_sessionmaker(engine))
    return lambda: retention.purge_processed_messages(PROCESSED_RETENTION)


JOBS: dict[str, tuple[int, JobFactory]] = {
    "purge-outbox": (7_315_420_101, _purge_outbox),
    "purge-processed": (7_315_420_102, _purge_processed),
}


async def run_job(name: str, engine: AsyncEngine) -> bool:
    lock_key, factory = JOBS[name]
    ran = await run_exclusive(engine, lock_key, factory(engine))
    logger.info("job finished", job=name, ran=ran)
    return ran


async def _main(name: str) -> None:
    settings = AppSettings()
    engine = create_async_engine(settings.db.sqlalchemy_url())
    try:
        await run_job(name, engine)
    finally:
        await engine.dispose()


def main() -> None:
    parser = argparse.ArgumentParser(prog="my-service-job")
    parser.add_argument("name", choices=sorted(JOBS))
    configure_logging()
    asyncio.run(_main(parser.parse_args().name))
```

Exit code `0` also when another instance held the lock (`ran=False` in the log): a skipped run is not a failure.

## In-process scheduling (only when no CronJob is available)
With APScheduler 3.x, `max_instances=1` and `coalesce=True` cover one process; the advisory lock covers all of
them. Every replica schedules, one wins each tick. APScheduler ships no type information: add `apscheduler` to the
mypy `ignore_missing_imports` overrides next to `aiokafka`.

### `src/my_service/scheduler.py`

```python
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy.ext.asyncio import AsyncEngine

from my_service.jobs import JOBS, run_job


def build_scheduler(engine: AsyncEngine, interval_seconds: dict[str, int]) -> AsyncIOScheduler:
    scheduler = AsyncIOScheduler(job_defaults={"max_instances": 1, "coalesce": True})
    for name, seconds in interval_seconds.items():
        if name not in JOBS:
            raise KeyError(name)
        scheduler.add_job(run_job, "interval", seconds=seconds, args=[name, engine], id=name)
    return scheduler
```

Start it in the lifespan (`scheduler.start()`), stop it before the engine is disposed (`scheduler.shutdown(wait=True)`,
`python-graceful-shutdown` §4). Prefer the CronJob: it survives replica churn and keeps jobs out of request pods.

## Tests
### `tests/integration/test_jobs.py`

```python
import asyncio
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncEngine, async_sessionmaker

from my_service.jobs import JOBS, run_job
from my_service.repositories.exclusive import run_exclusive
from my_service.repositories.orm import OutboxRow
from my_service.repositories.retention import SqlRetention
from my_service.scheduler import build_scheduler

LOCK = 7_315_499_001


async def test_runExclusive_concurrentCallers_onlyOneRunsTheJob(engine: AsyncEngine) -> None:
    running = 0
    peak = 0
    runs = 0

    async def job() -> None:
        nonlocal running, peak, runs
        running += 1
        peak = max(peak, running)
        runs += 1
        await asyncio.sleep(0.3)
        running -= 1

    results = await asyncio.gather(*(run_exclusive(engine, LOCK, job) for _ in range(5)))
    assert sorted(results) == [False, False, False, False, True]
    assert (runs, peak) == (1, 1)
    assert await run_exclusive(engine, LOCK, job) is True


async def test_runExclusive_failingJob_releasesTheLock(engine: AsyncEngine) -> None:
    async def failing() -> None:
        raise RuntimeError("boom")

    with pytest.raises(RuntimeError):
        await run_exclusive(engine, LOCK + 1, failing)

    async def ok() -> None:
        return None

    assert await run_exclusive(engine, LOCK + 1, ok) is True


async def _add_outbox(engine: AsyncEngine, published_days_ago: int | None) -> None:
    published = (
        None
        if published_days_ago is None
        else datetime.now(UTC) - timedelta(days=published_days_ago)
    )
    async with async_sessionmaker(engine)() as s, s.begin():
        s.add(
            OutboxRow(
                id=uuid4(), topic="t", key="k", event_type="E", payload={}, published_at=published
            )
        )


async def _outbox_count(engine: AsyncEngine) -> int:
    async with async_sessionmaker(engine)() as s:
        return await s.scalar(select(func.count()).select_from(OutboxRow)) or 0


async def test_purgePublishedOutbox_deletesOnlyExpiredPublishedRowsInBatches(
    engine: AsyncEngine, clean_tables: None
) -> None:
    for _ in range(5):
        await _add_outbox(engine, published_days_ago=10)
    await _add_outbox(engine, published_days_ago=1)
    await _add_outbox(engine, published_days_ago=None)
    retention = SqlRetention(async_sessionmaker(engine), batch_size=2)
    assert await retention.purge_published_outbox(timedelta(days=7)) == 5
    assert await _outbox_count(engine) == 2


async def test_runJob_purgeOutbox_runsThroughTheRegistry(
    engine: AsyncEngine, clean_tables: None
) -> None:
    await _add_outbox(engine, published_days_ago=30)
    assert await run_job("purge-outbox", engine) is True
    assert await _outbox_count(engine) == 0


async def test_scheduler_twoReplicas_neverRunTheJobConcurrently(
    engine: AsyncEngine, monkeypatch: pytest.MonkeyPatch
) -> None:
    state = {"running": 0, "peak": 0, "runs": 0}

    async def body() -> None:
        state["running"] += 1
        state["peak"] = max(state["peak"], state["running"])
        state["runs"] += 1
        await asyncio.sleep(0.25)
        state["running"] -= 1

    def factory(_: AsyncEngine) -> Callable[[], Awaitable[object]]:
        return body

    monkeypatch.setitem(JOBS, "slow", (LOCK + 2, factory))
    replicas = [build_scheduler(engine, {"slow": 1}) for _ in range(2)]
    for replica in replicas:
        replica.start()
    await asyncio.sleep(3.5)
    for replica in replicas:
        replica.shutdown(wait=False)
    await asyncio.sleep(0.4)
    assert state["runs"] >= 2
    assert state["peak"] == 1
```


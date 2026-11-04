---
name: python-integration-tests
description: >
  Python integration tests with testcontainers-python (PostgreSQL, Redis, Kafka) and pytest markers separating unit
  from integration, including Alembic migration checks. Use when behaviour depends on real database or broker
  semantics that fakes cannot prove.
tier: should
applies_to: [rest, worker]
depends_on: [python-unit-tests, python-persistence]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

# Python Integration Tests Skill
## When to use
When a unit test with a fake cannot prove the behaviour: a SQL adapter, a migration, optimistic
locking, a broker round-trip, or a full request through the real app wiring.

## Layout

```
tests/
├── unit/                       # no I/O; default run
└── integration/
    ├── conftest.py             # session-scoped containers, migrated engine
    ├── test_sql_order_repository.py
    └── test_orders_api.py
```

The intended path is PostgreSQL via testcontainers, the engine used in production. The examples
below were executed against SQLite (`aiosqlite`) as a stand-in because no Docker was available; the
container fixtures, `asyncpg` and Alembic-on-Postgres parts follow the library docs and were not run here.

## Dependencies
```toml
[dependency-groups]
dev = ["testcontainers[postgres]>=4.8", "pytest-asyncio>=0.24", "asgi-lifespan>=2.1"]
```
The pytest settings live in the one `[tool.pytest.ini_options]` table from `python-unit-tests`, which
already sets both loop scopes to `"session"` (do not add a second table or repeat the keys):
```toml
asyncio_default_fixture_loop_scope = "session"   # the session-scoped engine fixture lives on one loop...
asyncio_default_test_loop_scope = "session"      # ...so the tests that use it must run on that same loop
```
Both settings are required (pytest-asyncio >= 0.24): with only the default function-scoped test loop, a
session-scoped async engine or pool is used from a different loop and fails with
`RuntimeError: ... attached to a different loop`.

## 1. Marker segregation
Integration tests carry a marker, applied automatically by directory so nobody forgets it.

```python
# tests/conftest.py   (the hook receives every collected item, so match on the path)
def pytest_collection_modifyitems(items: list[pytest.Item]) -> None:
    for item in items:
        if "integration" in item.path.parts:
            item.add_marker(pytest.mark.integration)
```

```
uv run pytest -m "not integration"     # fast loop, no Docker
uv run pytest -m integration           # separate CI job
```
`pytest` exits 5 when the marker selects nothing (no integration test yet); CI tolerates exactly that code (see `python-ci`).
`--strict-markers` is on (see `python-unit-tests`); unit tests must never need Docker.

## 2. One container per session, one clean state per test
```python
@pytest.fixture(scope="session")
def postgres_url() -> Iterator[str]:
    with PostgresContainer("postgres:16-alpine", driver="asyncpg") as pg:
        yield pg.get_connection_url()

@pytest.fixture(scope="session")
async def engine(postgres_url: str) -> AsyncIterator[AsyncEngine]:
    engine = create_async_engine(postgres_url)
    await run_alembic_upgrade(engine)          # project helper, defined below
    yield engine
    await engine.dispose()

@pytest.fixture
async def session(engine: AsyncEngine) -> AsyncIterator[AsyncSession]:
    async with engine.connect() as conn:
        tx = await conn.begin()
        async with AsyncSession(bind=conn, join_transaction_mode="create_savepoint") as s:
            yield s
        await tx.rollback()
```
Pin image tags to the production major version; never `latest`.

`run_alembic_upgrade` is a project helper, not a library function. A minimal version runs the real
migrations on the engine's connection (`alembic/env.py` must then use
`context.config.attributes.get("connection")` instead of creating its own engine):

```python
async def run_alembic_upgrade(engine: AsyncEngine) -> None:
    def upgrade(connection: Connection) -> None:
        config = Config("alembic.ini")
        config.attributes["connection"] = connection
        command.upgrade(config, "head")

    async with engine.begin() as conn:
        await conn.run_sync(upgrade)
```

## 3. What to assert
```python
async def test_save_staleVersion_raisesOrderVersionConflictError(session: AsyncSession) -> None:
    repo = SqlOrderRepository(session)
    order = an_order()
    await repo.add(order)
    await repo.save(order.pay(), expected_version=1)
    with pytest.raises(OrderVersionConflictError):
        await repo.save(order, expected_version=1)      # version 1 is stale now
```
- Repository adapters: round-trip, unique-constraint translation, optimistic-lock conflict, pagination ordering.
- Migrations: `upgrade head` on empty DB succeeds; models match schema (`alembic check`).
- API: `ASGITransport(app=app)` inside `LifespanManager(app)` (from `asgi-lifespan`; `ASGITransport` does not
  run the lifespan, so `app.state` would be empty) with real settings pointing at the containers; assert
  status and problem+json. `with TestClient(app)` also runs the lifespan.

## 4. Other dependencies
HTTP downstreams are stubbed with `respx` (unit/integration) or a WireMock container; brokers and caches
use their testcontainers module. Use `wait_for_logs`/the module's readiness strategy, never `sleep`.

## 5. Speed and isolation
Reuse the session container, isolate tests with transaction rollback or per-test schema, and run
the integration job in parallel with the unit job. Integration tests are fewer and broader than unit tests.

## Do / Don't
- ✅ Run the real migrations against the real engine type used in production (not SQLite stand-ins).
- ✅ Keep tests independent: each starts from a known state and cleans up.
- ✅ Give the CI job a Docker-capable runner.
- ❌ Testing business logic here that a fake-based unit test covers.
- ❌ Shared mutable data between tests, or reliance on execution order.
- ❌ `time.sleep` for readiness; unpinned image tags.
- ❌ Mocking the database in a test named integration.

## Cross-references
- `python-persistence` — the adapters and migrations under test.
- `python-unit-tests` — the default suite and marker config.
- `python-ci` — separate integration job.

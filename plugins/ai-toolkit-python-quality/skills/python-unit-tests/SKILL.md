---
name: python-unit-tests
description: >
  Python pytest unit tests — positive, negative and edge cases, method_condition_expectedResult naming, fixtures,
  fakes at the boundary, parametrize, coverage threshold. Use when a module is created or a behaviour changes. Real
  DB/broker tests live in `python-integration-tests`.
tier: must
applies_to: [rest, worker, cli, library]
depends_on: [python-code-structure]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

# Python Unit Tests Skill
## When to use
Whenever you add a module, fix a bug (write the failing test first) or change behaviour.

## Layout

```
tests/
├── conftest.py                 # shared fixtures: fake clock, app factory
├── fakes/                      # in-memory implementations of Protocols
│   └── in_memory_order_repository.py
└── unit/
    └── services/test_checkout_service.py    # mirrors src/my_service/services/checkout_service.py
```

## Dependencies
```toml
[dependency-groups]
dev = ["pytest>=8.3", "pytest-asyncio>=0.24", "pytest-cov>=5.0", "httpx>=0.27", "asgi-lifespan>=2.1"]

[tool.pytest.ini_options]
asyncio_mode = "auto"
asyncio_default_fixture_loop_scope = "session"    # one loop for fixtures and tests: the same block
asyncio_default_test_loop_scope = "session"       # `python-integration-tests` needs (never repeat these keys)
addopts = "--strict-markers"                      # no --cov here: see section 7
markers = ["integration: needs real infrastructure (see python-integration-tests)"]
testpaths = ["tests"]

[tool.coverage.run]
source = ["my_service"]
branch = true

[tool.coverage.report]
fail_under = 85
exclude_also = ["if TYPE_CHECKING:", "^\\s*\\.\\.\\.$"]
```

This is the single `[tool.pytest.ini_options]` table for the project; `python-integration-tests` adds
only its dependencies and marker hook, not a second table (TOML rejects duplicate keys). Checked by running
unit and integration tests together under it.

Keep `--cov` and thresholds out of `addopts`: a threshold there makes every single-test run
(`pytest tests/unit/test_x.py::test_a`) exit non-zero because one test cannot cover the service.

## 1. Naming: `method_condition_expectedResult`
One behaviour per test; the name is the specification.

```python
async def test_checkout_gatewayDeclines_raisesPaymentDeclinedError() -> None: ...
async def test_checkout_validOrder_returnsReceiptWithChargeId() -> None: ...
def test_total_emptyCart_returnsZero() -> None: ...
```

Mirror the source tree: `services/checkout_service.py` -> `tests/unit/services/test_checkout_service.py`.
(Select `N` in ruff and add `"N802"` to the per-file ignores for `tests/` to allow the camel-cased
suffix; without `N` selected the ignore is a no-op, see `python-static-analysis`.)

## 2. Cover three kinds of case
For every public behaviour: **positive** (happy path), **negative** (every raised error / rejected
input), **edge** (empty, boundary, duplicate, `None`, max size). Line coverage is a floor, not the goal:
assert outcomes and state, not that code ran.

## 3. Fakes at the boundary, not mocks of the unit
Test the real class with fake collaborators implementing its `Protocol`. Never mock the class under test.

```python
class FakePaymentGateway:
    def __init__(self, *, decline: bool = False) -> None:
        self.charges: list[tuple[str, int]] = []
        self._decline = decline

    async def charge(self, customer_id: str, cents: int) -> str:
        if self._decline:
            raise PaymentDeclinedError(customer_id=customer_id)
        self.charges.append((customer_id, cents))
        return "ch_1"

async def test_checkout_gatewayDeclines_raisesPaymentDeclinedError(fixed_clock: Clock) -> None:
    service = CheckoutService(FakePaymentGateway(decline=True), fixed_clock)
    with pytest.raises(PaymentDeclinedError):
        await service.checkout(an_order())
```

Fakes hold state you can assert on and are reused across tests. Use `unittest.mock`/`AsyncMock` only
for one-off interaction checks on a boundary you cannot fake cheaply; never `patch()` internals of
your own modules, and never patch `datetime` (inject a `Clock`).

## 4. Fixtures and builders
Fixtures provide collaborators (`fixed_clock`, `fake_repo`); plain builder functions create test data
with overridable defaults (`an_order(total_cents=0)`). Keep fixtures function-scoped unless
construction is expensive and the object is immutable.

## 5. Parametrize tables
```python
@pytest.mark.parametrize(
    ("cents", "valid"),
    [(0, False), (1, True), (100_000_000, True), (100_000_001, False)],
    ids=["zero", "min", "max", "above_max"],
)
def test_positiveCents_boundaries_acceptsOnlyInRange(cents: int, valid: bool) -> None:
    ...
```

## 6. HTTP layer tests
Use `httpx.AsyncClient(transport=ASGITransport(app=app))` with `app.dependency_overrides` pointing
to fakes. `ASGITransport` does **not** run the lifespan, so anything the lifespan puts on `app.state`
is missing (`AttributeError` in providers). Wrap the app in `asgi_lifespan.LifespanManager`, or use the
sync `with TestClient(app) as client:` (the `with` runs the lifespan; with recent Starlette
`TestClient` emits a `StarletteDeprecationWarning` asking for `httpx2` in place of `httpx`, which is harmless
but fails the run under `-W error`):

```python
@pytest.fixture
async def client() -> AsyncIterator[AsyncClient]:
    app = create_app()
    async with LifespanManager(app):
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            yield client
```

Assert status, `application/problem+json` and `code` for errors.

## 7. Coverage gate
`fail_under` in `[tool.coverage.report]` (start at 85, ratchet upward) makes a coverage drop fail the
build, but only on runs that measure coverage: the CI unit job runs
`uv run pytest -m "not integration" --cov` (see `python-ci`); local single-test runs stay plain. Exclude
only true boilerplate (`if TYPE_CHECKING:`, `...` in Protocols) via `exclude_also`.

## Do / Don't
- ✅ Arrange / act / assert, one behaviour per test, deterministic (no sleeps, real clock, network, randomness).
- ✅ Test through the public interface; assert on results and fake state.
- ✅ Write the failing test before fixing a bug.
- ❌ Mocking the class under test, or asserting `mock.assert_called_once()` as the only check.
- ❌ Tests with no assertions, or `try/except` around assertions.
- ❌ Shared mutable module-level state between tests; order-dependent tests.
- ❌ `@pytest.mark.skip` without a ticket reference.

## Cross-references
- `python-code-structure` — Protocols and injection that make fakes possible.
- `python-integration-tests` — what unit tests deliberately do not cover.
- `python-static-analysis` — lint/type rules applied to tests too.
- `python-error-handling`, `python-input-validation` — negative cases to cover.

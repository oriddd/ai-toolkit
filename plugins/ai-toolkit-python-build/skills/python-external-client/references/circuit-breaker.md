# python-external-client — circuit breaker

Back to [`SKILL.md`](../SKILL.md) §4. Retries absorb a blip; a circuit breaker stops a dead dependency from eating
every request's full retry budget and from being hammered while it recovers. Add it when a dependency can be down
for minutes, not before. `pybreaker` has no asyncio support (its async mode is Tornado), so the breaker here is a
small class with an injectable clock. It lives in `clients/circuit_breaker.py` and is shared by all clients.

### `src/my_service/clients/circuit_breaker.py`

```python
import time
from collections.abc import Callable
from enum import StrEnum

import structlog

logger = structlog.get_logger()


class CircuitState(StrEnum):
    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"


class CircuitOpenError(Exception):
    pass


class CircuitBreaker:
    def __init__(
        self,
        name: str,
        failure_threshold: int = 5,
        recovery_seconds: float = 30.0,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._name = name
        self._failure_threshold = failure_threshold
        self._recovery_seconds = recovery_seconds
        self._clock = clock
        self._state = CircuitState.CLOSED
        self._failures = 0
        self._opened_at = 0.0
        self._trial_in_flight = False

    @property
    def state(self) -> CircuitState:
        return self._state

    def before_call(self) -> None:
        if self._state is CircuitState.OPEN:
            if self._clock() - self._opened_at < self._recovery_seconds:
                raise CircuitOpenError(self._name)
            self._transition(CircuitState.HALF_OPEN)
        if self._state is CircuitState.HALF_OPEN:
            if self._trial_in_flight:
                raise CircuitOpenError(self._name)
            self._trial_in_flight = True

    def record_success(self) -> None:
        self._failures = 0
        self._trial_in_flight = False
        if self._state is not CircuitState.CLOSED:
            self._transition(CircuitState.CLOSED)

    def record_failure(self) -> None:
        self._trial_in_flight = False
        self._failures += 1
        if self._state is CircuitState.HALF_OPEN or self._failures >= self._failure_threshold:
            self._opened_at = self._clock()
            self._transition(CircuitState.OPEN)

    def record_aborted(self) -> None:
        self._trial_in_flight = False

    def _transition(self, new_state: CircuitState) -> None:
        logger.warning("circuit state changed", circuit=self._name, old=self._state, new=new_state)
        self._state = new_state
```

- `CLOSED` counts consecutive failures; at the threshold it goes `OPEN` and `before_call` raises `CircuitOpenError`
  with no network call.
- After `recovery_seconds`, the next call moves it to `HALF_OPEN` and is the only trial; concurrent callers are still
  rejected. A successful trial closes the circuit, a failed one reopens it for another full period.
- `record_aborted` releases a trial that was cancelled (client disconnect, timeout above the client), so the circuit
  never stays stuck waiting for a verdict that cannot arrive.
- It is single-process state: with N replicas each has its own breaker, which is what you want for connection-level
  failures. Count only dependency failures; a `404` or `422` is a healthy answer.

## Wiring: the breaker wraps the whole retried call
One failure for the breaker is a call that exhausted its retries (or a 5xx that is not retried), not each attempt:

### `src/my_service/clients/billing/http_billing_client.py`

```python
from http import HTTPStatus
from urllib.parse import quote

import httpx
from pydantic import ValidationError

from my_service.clients.billing.retry import RETRYABLE_STATUSES, RetryableStatusError, RetryPolicy
from my_service.clients.billing.wire import CreditWire
from my_service.clients.circuit_breaker import CircuitBreaker, CircuitOpenError
from my_service.errors.base import DependencyBadResponseError, DependencyUnavailableError
from my_service.errors.domain import CustomerNotFoundError
from my_service.models.credit import CustomerCredit

DEPENDENCY = "billing"


class HttpBillingClient:
    def __init__(
        self, http: httpx.AsyncClient, retry_policy: RetryPolicy, breaker: CircuitBreaker
    ) -> None:
        self._http = http
        self._retry_policy = retry_policy
        self._breaker = breaker

    async def get_credit(self, customer_id: str) -> CustomerCredit:
        response = await self._get(f"/v1/customers/{quote(customer_id, safe='')}/credit")
        if response.status_code == HTTPStatus.NOT_FOUND:
            raise CustomerNotFoundError(customer_id=customer_id)
        if response.is_server_error:
            raise DependencyUnavailableError(dependency=DEPENDENCY)
        response.raise_for_status()
        try:
            wire = CreditWire.model_validate_json(response.content)
        except ValidationError as exc:
            raise DependencyBadResponseError(dependency=DEPENDENCY) from exc
        return CustomerCredit(customer_id=wire.customerId, available_cents=wire.availableCents)

    async def _get(self, path: str) -> httpx.Response:
        try:
            self._breaker.before_call()
        except CircuitOpenError as exc:
            raise DependencyUnavailableError(dependency=DEPENDENCY) from exc
        try:
            response = await self._get_with_retries(path)
        except DependencyUnavailableError:
            self._breaker.record_failure()
            raise
        except BaseException:
            self._breaker.record_aborted()
            raise
        if response.is_server_error:
            self._breaker.record_failure()
        else:
            self._breaker.record_success()
        return response

    async def _get_with_retries(self, path: str) -> httpx.Response:
        try:
            async for attempt in self._retry_policy.attempts():
                with attempt:
                    response = await self._http.get(path)
                    if response.status_code in RETRYABLE_STATUSES:
                        raise RetryableStatusError(response.status_code)
                    return response
        except (httpx.TransportError, RetryableStatusError) as exc:
            raise DependencyUnavailableError(dependency=DEPENDENCY) from exc
        raise AssertionError("unreachable: tenacity re-raises after the last attempt")
```

An open circuit becomes the same `DependencyUnavailableError` (503) callers already handle, with the
`CircuitOpenError` as `__cause__`. Build one `CircuitBreaker("billing", failure_threshold=5, recovery_seconds=30)`
per dependency in the lifespan next to its `httpx.AsyncClient`, and log or export the state change
(`python-observability` §4).

## Tests (fake clock, `respx`)
### `tests/unit/test_circuit_breaker.py`

```python
import httpx
import pytest
import respx
from tenacity.wait import wait_none

from my_service.clients.billing.http_billing_client import HttpBillingClient
from my_service.clients.billing.retry import RetryPolicy
from my_service.clients.circuit_breaker import CircuitBreaker, CircuitOpenError, CircuitState
from my_service.errors.base import DependencyUnavailableError
from my_service.errors.domain import CustomerNotFoundError


class Clock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


@pytest.fixture
def clock() -> Clock:
    return Clock()


@pytest.fixture
def breaker(clock: Clock) -> CircuitBreaker:
    return CircuitBreaker("dep", failure_threshold=3, recovery_seconds=30, clock=clock)


def _trip(breaker: CircuitBreaker) -> None:
    for _ in range(3):
        breaker.before_call()
        breaker.record_failure()


def test_closed_belowThreshold_staysClosed(breaker: CircuitBreaker) -> None:
    for _ in range(2):
        breaker.before_call()
        breaker.record_failure()
    breaker.before_call()
    breaker.record_success()
    assert breaker.state is CircuitState.CLOSED


def test_open_afterThresholdFailures_rejectsCalls(breaker: CircuitBreaker) -> None:
    _trip(breaker)
    assert breaker.state is CircuitState.OPEN
    with pytest.raises(CircuitOpenError):
        breaker.before_call()


def test_open_afterRecoveryTime_allowsExactlyOneTrial(
    breaker: CircuitBreaker, clock: Clock
) -> None:
    _trip(breaker)
    clock.now = 31
    breaker.before_call()
    assert breaker.state is CircuitState.HALF_OPEN
    with pytest.raises(CircuitOpenError):
        breaker.before_call()


def test_halfOpen_trialSucceeds_closesCircuit(breaker: CircuitBreaker, clock: Clock) -> None:
    _trip(breaker)
    clock.now = 31
    breaker.before_call()
    breaker.record_success()
    assert breaker.state is CircuitState.CLOSED
    breaker.before_call()


def test_halfOpen_trialFails_reopensForAnotherRecoveryPeriod(
    breaker: CircuitBreaker, clock: Clock
) -> None:
    _trip(breaker)
    clock.now = 31
    breaker.before_call()
    breaker.record_failure()
    assert breaker.state is CircuitState.OPEN
    clock.now = 60
    with pytest.raises(CircuitOpenError):
        breaker.before_call()
    clock.now = 62
    breaker.before_call()
    assert breaker.state.value == "half_open"


def test_halfOpen_trialAborted_allowsNewTrial(breaker: CircuitBreaker, clock: Clock) -> None:
    _trip(breaker)
    clock.now = 31
    breaker.before_call()
    breaker.record_aborted()
    breaker.before_call()


@respx.mock(base_url="http://billing")
async def test_client_openCircuit_failsFastWithoutCallingDependency(
    respx_mock: respx.MockRouter, breaker: CircuitBreaker, clock: Clock
) -> None:
    route = respx_mock.get("/v1/customers/c-1/credit").mock(return_value=httpx.Response(503))
    async with httpx.AsyncClient(base_url="http://billing") as http:
        client = HttpBillingClient(http, RetryPolicy(max_attempts=1, wait=wait_none()), breaker)
        for _ in range(3):
            with pytest.raises(DependencyUnavailableError):
                await client.get_credit("c-1")
        assert breaker.state is CircuitState.OPEN
        calls_when_tripped = route.call_count
        with pytest.raises(DependencyUnavailableError) as rejected:
            await client.get_credit("c-1")
        assert route.call_count == calls_when_tripped
        assert isinstance(rejected.value.__cause__, CircuitOpenError)

        clock.now = 31
        route.mock(
            return_value=httpx.Response(200, json={"customerId": "c-1", "availableCents": 7})
        )
        credit = await client.get_credit("c-1")
        assert credit.available_cents == 7
        assert breaker.state.value == "closed"


@respx.mock(base_url="http://billing")
async def test_client_notFound_isNotADependencyFailure(
    respx_mock: respx.MockRouter, breaker: CircuitBreaker
) -> None:
    respx_mock.get("/v1/customers/c-1/credit").mock(return_value=httpx.Response(404))
    async with httpx.AsyncClient(base_url="http://billing") as http:
        client = HttpBillingClient(http, RetryPolicy(max_attempts=1, wait=wait_none()), breaker)
        for _ in range(5):
            with pytest.raises(CustomerNotFoundError):
                await client.get_credit("c-1")
    assert breaker.state is CircuitState.CLOSED
```


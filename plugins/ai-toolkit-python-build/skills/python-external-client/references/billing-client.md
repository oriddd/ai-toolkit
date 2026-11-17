# python-external-client — the billing client package

Back to [`SKILL.md`](../SKILL.md) §1 to §6. The port, the private wire model, the retry policy, the transport factory
and the `respx` tests. The adapter itself, wrapped by the circuit breaker, is in `circuit-breaker.md`.

## Domain result and port

### `src/my_service/models/credit.py`

```python
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class CustomerCredit:
    customer_id: str
    available_cents: int
```

### `src/my_service/clients/billing/port.py`

```python
from typing import Protocol

from my_service.models.credit import CustomerCredit


class BillingGateway(Protocol):
    async def get_credit(self, customer_id: str) -> CustomerCredit: ...
```

## Wire model, retry policy, transport

### `src/my_service/clients/billing/wire.py`

```python
from pydantic import BaseModel, ConfigDict


class CreditWire(BaseModel):
    model_config = ConfigDict(extra="ignore")

    customerId: str  # noqa: N815 - wire name
    availableCents: int  # noqa: N815 - wire name
```

### `src/my_service/clients/billing/retry.py`

```python
from http import HTTPStatus

import httpx
from tenacity import (
    AsyncRetrying,
    retry_if_exception_type,
    stop_after_attempt,
    stop_after_delay,
    wait_random_exponential,
)
from tenacity.wait import wait_base  # not re-exported by `tenacity` itself

RETRYABLE_STATUSES = frozenset(
    {
        HTTPStatus.TOO_MANY_REQUESTS,
        HTTPStatus.BAD_GATEWAY,
        HTTPStatus.SERVICE_UNAVAILABLE,
        HTTPStatus.GATEWAY_TIMEOUT,
    }
)


class RetryableStatusError(Exception):
    def __init__(self, status_code: int) -> None:
        super().__init__(f"retryable status {status_code}")
        self.status_code = status_code


class RetryPolicy:
    def __init__(
        self, max_attempts: int, max_delay_seconds: float = 10.0, wait: wait_base | None = None
    ) -> None:
        self._max_attempts = max_attempts
        self._max_delay_seconds = max_delay_seconds
        self._wait = wait or wait_random_exponential(multiplier=0.2, max=2.0)  # jittered backoff

    def attempts(self) -> AsyncRetrying:
        return AsyncRetrying(
            retry=retry_if_exception_type((httpx.TransportError, RetryableStatusError)),
            stop=stop_after_attempt(self._max_attempts) | stop_after_delay(self._max_delay_seconds),
            wait=self._wait,
            reraise=True,
        )
```

### `src/my_service/clients/billing/transport.py`

```python
import httpx

from my_service.config.settings import BillingSettings


def build_billing_http_client(settings: BillingSettings) -> httpx.AsyncClient:
    return httpx.AsyncClient(
        base_url=str(settings.base_url),
        timeout=httpx.Timeout(
            settings.read_timeout_seconds, connect=settings.connect_timeout_seconds
        ),
        limits=httpx.Limits(max_connections=50, max_keepalive_connections=10),
        headers={"Authorization": f"Bearer {settings.api_key.get_secret_value()}"},
        follow_redirects=False,
    )
```

## Tests

### `tests/unit/test_billing_client.py`

```python
from collections.abc import AsyncIterator

import httpx
import pytest
import respx
from tenacity.wait import wait_none

from my_service.clients.billing.http_billing_client import HttpBillingClient
from my_service.clients.billing.retry import RetryPolicy
from my_service.clients.billing.transport import build_billing_http_client
from my_service.clients.circuit_breaker import CircuitBreaker
from my_service.config.settings import BillingSettings
from my_service.errors.base import DependencyBadResponseError, DependencyUnavailableError
from my_service.errors.domain import CustomerNotFoundError

BASE_URL = "http://billing"
CREDIT_PATH = "/v1/customers/c-1/credit"
OK = {"customerId": "c-1", "availableCents": 7, "futureField": True}


@pytest.fixture
async def billing() -> AsyncIterator[HttpBillingClient]:
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=1.0) as http:
        yield HttpBillingClient(
            http, RetryPolicy(max_attempts=3, wait=wait_none()), CircuitBreaker("billing")
        )


@respx.mock(base_url=BASE_URL)
async def test_getCredit_ok_mapsWireToDomainAndIgnoresUnknownFields(
    respx_mock: respx.MockRouter, billing: HttpBillingClient
) -> None:
    respx_mock.get(CREDIT_PATH).mock(return_value=httpx.Response(200, json=OK))
    credit = await billing.get_credit("c-1")
    assert (credit.customer_id, credit.available_cents) == ("c-1", 7)


@respx.mock(base_url=BASE_URL)
async def test_getCredit_503ThenOk_retriesAndSucceeds(
    respx_mock: respx.MockRouter, billing: HttpBillingClient
) -> None:
    route = respx_mock.get(CREDIT_PATH).mock(
        side_effect=[httpx.Response(503), httpx.Response(200, json=OK)]
    )
    await billing.get_credit("c-1")
    assert route.call_count == 2


@respx.mock(base_url=BASE_URL)
async def test_getCredit_notFound_raisesCustomerNotFoundWithoutRetry(
    respx_mock: respx.MockRouter, billing: HttpBillingClient
) -> None:
    route = respx_mock.get(CREDIT_PATH).mock(return_value=httpx.Response(404))
    with pytest.raises(CustomerNotFoundError):
        await billing.get_credit("c-1")
    assert route.call_count == 1


@respx.mock(base_url=BASE_URL)
async def test_getCredit_500_isUnavailableWithoutRetry(
    respx_mock: respx.MockRouter, billing: HttpBillingClient
) -> None:
    route = respx_mock.get(CREDIT_PATH).mock(return_value=httpx.Response(500))
    with pytest.raises(DependencyUnavailableError):
        await billing.get_credit("c-1")
    assert route.call_count == 1


@respx.mock(base_url=BASE_URL)
async def test_getCredit_timeoutOnEveryAttempt_isUnavailableWithCause(
    respx_mock: respx.MockRouter, billing: HttpBillingClient
) -> None:
    route = respx_mock.get(CREDIT_PATH).mock(side_effect=httpx.ConnectTimeout("slow"))
    with pytest.raises(DependencyUnavailableError) as raised:
        await billing.get_credit("c-1")
    assert route.call_count == 3
    assert isinstance(raised.value.__cause__, httpx.TransportError)


@respx.mock(base_url=BASE_URL)
async def test_getCredit_malformedBody_isBadResponse(
    respx_mock: respx.MockRouter, billing: HttpBillingClient
) -> None:
    respx_mock.get(CREDIT_PATH).mock(return_value=httpx.Response(200, json={"nope": 1}))
    with pytest.raises(DependencyBadResponseError):
        await billing.get_credit("c-1")


@respx.mock(base_url=BASE_URL)
async def test_getCredit_undocumented4xx_isOurBugNotUnavailable(
    respx_mock: respx.MockRouter, billing: HttpBillingClient
) -> None:
    respx_mock.get(CREDIT_PATH).mock(return_value=httpx.Response(400))
    with pytest.raises(httpx.HTTPStatusError):
        await billing.get_credit("c-1")


@respx.mock(base_url=BASE_URL)
async def test_getCredit_idNeedingEncoding_isPercentEncodedInThePath(
    respx_mock: respx.MockRouter, billing: HttpBillingClient
) -> None:
    route = respx_mock.get("/v1/customers/a%2F..%2Fadmin/credit").mock(
        return_value=httpx.Response(200, json=OK)
    )
    await billing.get_credit("a/../admin")
    assert route.call_count == 1


async def test_transport_buildsClientWithExplicitTimeoutsAndNoRedirects() -> None:
    settings = BillingSettings(read_timeout_seconds=3, connect_timeout_seconds=1)
    async with build_billing_http_client(settings) as http:
        assert http.timeout.read == 3
        assert http.timeout.connect == 1
        assert http.follow_redirects is False
```

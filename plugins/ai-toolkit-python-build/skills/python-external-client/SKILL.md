---
name: python-external-client
description: >
  Python / FastAPI outbound HTTP client — one httpx.AsyncClient per dependency with explicit timeouts, a Protocol
  port, tenacity retries for idempotent calls only, error mapping to typed domain errors, respx tests. Use when a
  service starts calling another HTTP API or an existing client is changed.
tier: should
applies_to: [rest, worker, cli]
depends_on: [python-code-structure, python-error-handling]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-11
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# Python External Client Skill
## When to use
Whenever the service calls another HTTP API (an internal microservice or a third party), or an existing
client gains an endpoint, a retry or a new error case.

## Layout
One sub-package per dependency; callers see only the port and the domain model.

```
src/my_service/
├── models/credit.py                  # domain result: CustomerCredit (frozen dataclass)
└── clients/billing/
    ├── port.py                       # BillingGateway Protocol: what services depend on
    ├── http_billing_client.py        # HttpBillingClient: the adapter (httpx)
    ├── wire.py                       # pydantic models of the dependency's JSON, private to the package
    ├── retry.py                      # RetryPolicy: which failures are retried, how often, how long
    └── transport.py                  # build_billing_http_client(settings) -> httpx.AsyncClient
```

`BillingSettings` (base URL, credentials as `SecretStr`, timeouts, attempts) lives in `config/` like every
settings class (`python-code-structure` §5).

## Dependencies
```toml
dependencies = ["httpx>=0.28", "tenacity>=9.0"]

[dependency-groups]
dev = ["respx>=0.22"]
```

## 1. The port and the domain result
Services and operations depend on the Protocol, never on httpx or the wire models.

```python
class BillingGateway(Protocol):                       # clients/billing/port.py
    async def get_credit(self, customer_id: str) -> CustomerCredit: ...
```

Wire models are tolerant readers: `ConfigDict(extra="ignore")` so a new field upstream does not break us,
named exactly as the dependency sends them (`customerId`, with `# noqa: N815 - wire name`), and mapped to the
domain model inside the adapter. They never leave the package.

## 2. One client per dependency, built in the lifespan
```python
def build_billing_http_client(settings: BillingSettings) -> httpx.AsyncClient:
    return httpx.AsyncClient(
        base_url=str(settings.base_url),
        timeout=httpx.Timeout(settings.read_timeout_seconds, connect=settings.connect_timeout_seconds),
        limits=httpx.Limits(max_connections=50, max_keepalive_connections=10),
        headers={"Authorization": f"Bearer {settings.api_key.get_secret_value()}"},
        follow_redirects=False,
    )
```

- Create it once in the lifespan, wrap it in the adapter, put the adapter on `app.state`, and
  `await client.aclose()` on shutdown (`python-fastapi-conventions` §7). A client per request throws away the
  connection pool; a module-level client cannot be closed or replaced in tests.
- Every client has an explicit `httpx.Timeout`; never `timeout=None`. httpx's default (5 s for everything)
  is a guess, not a decision.
- `follow_redirects=False` unless the API documents redirects: a redirect can carry the `Authorization`
  header to another host.
- Never `httpx.get(...)`, `requests` or any sync client inside `async def` (`python-fastapi-conventions` Do/Don't).

## 3. Build URLs safely
`base_url` is fixed by settings; only path segments vary, and each is percent-encoded:
`f"/v1/customers/{quote(customer_id, safe='')}/credit"`. Without `quote`, an id like `a/../admin` rewrites the
path on the downstream (path traversal). Query values go through `params=`, never string concatenation.
Never call a URL taken from user input (SSRF); see `python-security`.

## 4. Retries: idempotent calls, transient failures, bounded
```python
RETRYABLE_STATUSES = frozenset({HTTPStatus.TOO_MANY_REQUESTS, HTTPStatus.BAD_GATEWAY,
                                HTTPStatus.SERVICE_UNAVAILABLE, HTTPStatus.GATEWAY_TIMEOUT})

class RetryableStatusError(Exception):
    def __init__(self, status_code: int) -> None:
        super().__init__(f"retryable status {status_code}")
        self.status_code = status_code

class RetryPolicy:
    def __init__(self, max_attempts: int, max_delay_seconds: float = 10.0,
                 wait: wait_base | None = None) -> None:
        self._max_attempts = max_attempts
        self._max_delay_seconds = max_delay_seconds
        self._wait = wait or wait_random_exponential(multiplier=0.2, max=2.0)   # jittered backoff

    def attempts(self) -> AsyncRetrying:
        return AsyncRetrying(
            retry=retry_if_exception_type((httpx.TransportError, RetryableStatusError)),
            stop=stop_after_attempt(self._max_attempts) | stop_after_delay(self._max_delay_seconds),
            wait=self._wait,
            reraise=True,
        )
```

- Retry only **idempotent** requests (`GET`, `PUT`, `DELETE`), or a `POST` that carries an `Idempotency-Key`
  the dependency honours. A retried plain `POST` can charge a card twice.
- Retry only transient failures: transport errors (timeout, refused, reset) and 429/502/503/504. Never retry
  another 4xx: the answer will not change.
- Bound both attempts and total time, so retries fit inside the caller's own timeout.
- `wait` is injectable: tests pass `wait_none()` and run without sleeping.
- Retries multiply load on a struggling dependency; keep attempts small (3) and add a circuit breaker only
  when measurements show the need.

## 5. Map every outcome to the domain
```python
class HttpBillingClient:
    def __init__(self, http: httpx.AsyncClient, retry_policy: RetryPolicy) -> None:
        self._http = http
        self._retry_policy = retry_policy

    async def get_credit(self, customer_id: str) -> CustomerCredit:
        response = await self._get(f"/v1/customers/{quote(customer_id, safe='')}/credit")
        if response.status_code == HTTPStatus.NOT_FOUND:
            raise CustomerNotFoundError(customer_id=customer_id)
        if response.is_server_error:                  # a 5xx we did not retry (500): unavailable
            raise DependencyUnavailableError(dependency=DEPENDENCY)
        response.raise_for_status()                   # any other 4xx is our bug: 500, not 503
        try:
            wire = CreditWire.model_validate_json(response.content)
        except ValidationError as exc:                # contract broken upstream: 502
            raise DependencyBadResponseError(dependency=DEPENDENCY) from exc
        return CustomerCredit(customer_id=wire.customerId, available_cents=wire.availableCents)

    async def _get(self, path: str) -> httpx.Response:
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

The mapping follows `python-error-handling` §5: transport failure and 5xx -> `DependencyUnavailableError`
(503), each documented 4xx -> its own domain error, an undocumented 4xx -> 500, a body that does not match the
contract -> `DependencyBadResponseError` (502, catalogue entry `DEPENDENCY_BAD_RESPONSE`). Always `raise ... from exc`.
Do not log at each layer: the single handler logs (`python-observability`). The adapter never returns `None`
for "not found" or "failed".

Do not hold a database transaction open across a remote call: an operation calls the client first, then opens
its unit of work (`python-persistence` §3).

## 6. Testing
Unit-test the adapter with `respx`, the real `httpx.AsyncClient` and an injected no-wait retry policy:

```python
@pytest.fixture
async def billing() -> AsyncIterator[HttpBillingClient]:
    async with httpx.AsyncClient(base_url=BASE_URL, timeout=1.0) as http:
        yield HttpBillingClient(http, RetryPolicy(max_attempts=3, wait=wait_none()))

@respx.mock(base_url=BASE_URL)
async def test_getCredit_503ThenOk_retriesAndSucceeds(
    respx_mock: respx.MockRouter, billing: HttpBillingClient
) -> None:
    route = respx_mock.get(CREDIT_PATH).mock(
        side_effect=[httpx.Response(503), httpx.Response(200, json={"customerId": "c-1", "availableCents": 1})]
    )
    await billing.get_credit("c-1")
    assert route.call_count == 2
```

Cover, per endpoint: success mapping, each documented 4xx, 500 (no retry), 503-then-success, timeout on every
attempt (assert `call_count == max_attempts` and `__cause__`), malformed body, and an id that needs encoding.
Services and operations are tested with a hand-written `FakeBillingGateway` implementing the port
(`python-unit-tests` §3), never with respx.

## Do / Don't
- ✅ One `AsyncClient` per dependency, created and closed in the lifespan, explicit `Timeout`.
- ✅ A `Protocol` port and a domain result; wire models stay private to the client package.
- ✅ Retry idempotent calls on transport errors and 429/502/503/504 only, bounded by attempts and time.
- ✅ Percent-encode path segments; pass query values with `params=`.
- ❌ `httpx.AsyncClient()` inside a request handler or service method, or a module-level client.
- ❌ `requests` / sync `httpx.Client` in async code; `timeout=None`.
- ❌ Retrying a non-idempotent `POST` without an idempotency key; retrying 4xx.
- ❌ Returning `None`, `{}` or the raw `httpx.Response` to callers; leaking `httpx` exceptions past the adapter.
- ❌ Mocking `httpx` with `unittest.mock`; use respx for the adapter and fakes for its callers.

## Cross-references
- `python-code-structure` — the `clients/` layer, Protocols and settings.
- `python-error-handling` — the catalogue entries and the 503/502/500 mapping.
- [`python-security`](../python-security/SKILL.md) — SSRF and secrets for outbound calls.
- `python-unit-tests` — fakes for callers of the port.
- `python-observability` — `HTTPXClientInstrumentor` traces every outbound call.

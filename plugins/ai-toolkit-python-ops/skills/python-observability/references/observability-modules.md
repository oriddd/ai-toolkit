# python-observability — logging, correlation, metrics and tracing modules

Back to [`SKILL.md`](../SKILL.md) §1 to §4. `mask_pii` is in `python-security`'s `data-privacy.md`; the unit tests of
the masking and of the encrypted column are `tests/unit/test_privacy.py` in `auth-modules.md`.

## Logging

### `src/my_service/observability/logging.py`

```python
import logging

import structlog
from opentelemetry import trace
from structlog.typing import EventDict, Processor, WrappedLogger

from my_service.observability.pii_masking import mask_pii


def add_trace_id(_: WrappedLogger, __: str, event_dict: EventDict) -> EventDict:
    span = trace.get_current_span().get_span_context()
    if span.is_valid:  # joins this log line to its trace
        event_dict["trace_id"] = format(span.trace_id, "032x")
    return event_dict


SHARED: list[Processor] = [
    structlog.contextvars.merge_contextvars,
    structlog.processors.add_log_level,
    structlog.processors.TimeStamper(fmt="iso", utc=True),
    add_trace_id,
    mask_pii,  # PII never reaches a log line: `python-security` §7
]


def configure_logging(level: str = "INFO") -> None:
    structlog.configure(
        processors=[
            *SHARED,
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(logging.getLevelName(level)),
        cache_logger_on_first_use=True,
    )
    # stdlib loggers (uvicorn, sqlalchemy, httpx) go through the same processors: JSON, IDs included
    handler = logging.StreamHandler()
    handler.setFormatter(
        structlog.stdlib.ProcessorFormatter(
            foreign_pre_chain=SHARED,
            processors=[
                structlog.stdlib.ProcessorFormatter.remove_processors_meta,
                # else stdlib tracebacks render as "<traceback object>"
                structlog.processors.format_exc_info,
                structlog.processors.JSONRenderer(),
            ],
        )
    )
    logging.basicConfig(handlers=[handler], level=level, force=True)
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        logging.getLogger(name).handlers.clear()  # uvicorn installs its own text handlers
        logging.getLogger(name).propagate = True
```

## Correlation, metrics, tracing

### `src/my_service/observability/correlation.py`

```python
import re
from uuid import uuid4

import structlog
from starlette.datastructures import Headers, MutableHeaders
from starlette.types import ASGIApp, Message, Receive, Scope, Send

_VALID_ID = re.compile(r"[A-Za-z0-9._-]{1,64}")  # client-supplied: never trust length or charset


class CorrelationIdMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        headers = Headers(scope=scope)
        incoming = headers.get("x-request-id", "")
        # bounded, safe to log and echo
        request_id = incoming if _VALID_ID.fullmatch(incoming) else uuid4().hex
        structlog.contextvars.clear_contextvars()
        structlog.contextvars.bind_contextvars(request_id=request_id)

        async def send_with_id(message: Message) -> None:
            if message["type"] == "http.response.start":
                MutableHeaders(scope=message)["x-request-id"] = request_id
            await send(message)

        await self.app(scope, receive, send_with_id)
```

### `src/my_service/observability/metrics.py`

```python
import time

from prometheus_client import Counter, Histogram
from starlette.types import ASGIApp, Message, Receive, Scope, Send

REQUESTS = Counter("http_requests_total", "HTTP requests", ["method", "route", "status"])
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP latency",
    ["method", "route"],
    buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)


class MetricsMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        status = 500  # stays 500 if the app raises
        started = time.perf_counter()

        async def send_with_status(message: Message) -> None:
            nonlocal status
            if message["type"] == "http.response.start":
                status = message["status"]
            await send(message)

        try:
            await self.app(scope, receive, send_with_status)
        finally:
            route = getattr(scope.get("route"), "path", "unmatched")  # template, not raw path
            REQUESTS.labels(scope["method"], route, str(status)).inc()
            LATENCY.labels(scope["method"], route).observe(time.perf_counter() - started)
```

### `src/my_service/observability/tracing.py`

```python
from fastapi import FastAPI
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor


def configure_tracing(service_name: str, otlp_endpoint: str, app: FastAPI) -> None:
    provider = TracerProvider(resource=Resource.create({"service.name": service_name}))
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=otlp_endpoint)))
    trace.set_tracer_provider(provider)
    FastAPIInstrumentor.instrument_app(app)
    HTTPXClientInstrumentor().instrument()
```

## Tests

### `tests/unit/test_observability.py`

```python
import pytest
import structlog
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient
from opentelemetry import trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.sdk.trace import TracerProvider

from my_service.observability.correlation import CorrelationIdMiddleware
from my_service.observability.logging import add_trace_id
from my_service.observability.metrics import REQUESTS, MetricsMiddleware
from my_service.observability.tracing import configure_tracing


def _app() -> FastAPI:
    app = FastAPI()

    @app.get("/things/{thing_id}")
    async def thing(thing_id: str) -> dict[str, str]:
        return {"request_id": structlog.contextvars.get_contextvars()["request_id"]}

    app.add_middleware(MetricsMiddleware)
    app.add_middleware(CorrelationIdMiddleware)
    return app


async def _get(path: str, headers: dict[str, str] | None = None) -> tuple[str, str]:
    async with AsyncClient(transport=ASGITransport(app=_app()), base_url="http://t") as client:
        response = await client.get(path, headers=headers or {})
    return response.headers["x-request-id"], response.json()["request_id"]


async def test_correlationId_validIncomingId_isEchoedAndBoundForTheRequest() -> None:
    echoed, bound = await _get("/things/1", {"X-Request-ID": "abc-123"})
    assert echoed == bound == "abc-123"


@pytest.mark.parametrize("incoming", ["x" * 65, "bad id\t", "a;b"])
async def test_correlationId_unsafeIncomingId_isReplacedByAGeneratedOne(incoming: str) -> None:
    echoed, bound = await _get("/things/1", {"X-Request-ID": incoming})
    assert echoed == bound
    assert echoed != incoming
    assert len(echoed) == 32


async def test_metrics_labelsTheRouteTemplateNotTheRawPath() -> None:
    before = REQUESTS.labels("GET", "/things/{thing_id}", "200")._value.get()
    await _get("/things/42")
    assert REQUESTS.labels("GET", "/things/{thing_id}", "200")._value.get() == before + 1


def test_addTraceId_noActiveSpan_leavesTheEventUntouched() -> None:
    assert add_trace_id(None, "info", {"event": "x"}) == {"event": "x"}


def test_addTraceId_activeSpan_addsTheTraceId() -> None:
    tracer = TracerProvider().get_tracer("test")
    with tracer.start_as_current_span("work") as span:
        event = add_trace_id(None, "info", {"event": "x"})
    assert event["trace_id"] == format(span.get_span_context().trace_id, "032x")


def test_configureTracing_instrumentsTheAppAndOutboundHttpx() -> None:
    app = FastAPI()
    configure_tracing("my-service", "http://127.0.0.1:1/v1/traces", app)
    try:
        assert isinstance(trace.get_tracer_provider(), TracerProvider)
        assert HTTPXClientInstrumentor().is_instrumented_by_opentelemetry
    finally:
        FastAPIInstrumentor.uninstrument_app(app)
        HTTPXClientInstrumentor().uninstrument()
```

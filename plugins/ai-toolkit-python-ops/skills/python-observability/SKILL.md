---
name: python-observability
description: >
  Python / FastAPI observability — structlog JSON logs with contextvars correlation IDs, OpenTelemetry traces,
  prometheus-client metrics with low-cardinality labels. Use when creating a service or when production issues cannot
  be debugged.
tier: should
applies_to: [rest, worker]
depends_on: [python-code-structure]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-11
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# Python Observability Skill
## When to use
When a service is created, or whenever you cannot answer "what happened to this request?" from telemetry.

## Layout

```
src/my_service/observability/
├── logging.py          # structlog configuration
├── correlation.py      # middleware binding request/trace IDs into contextvars
├── tracing.py          # OpenTelemetry setup
└── metrics.py          # prometheus-client collectors + middleware
```

## Dependencies
```toml
dependencies = [
  "structlog>=24.4", "prometheus-client>=0.20",
  "opentelemetry-sdk>=1.27", "opentelemetry-exporter-otlp>=1.27",
  "opentelemetry-instrumentation-fastapi>=0.48b0", "opentelemetry-instrumentation-httpx>=0.48b0",
]
```

## 1. Structured JSON logs
One configuration at startup; every log line is a JSON object on stdout. Log events, not sentences:
`logger.info("order_created", order_id=..., total_cents=...)`.

```python
from opentelemetry import trace
from structlog.typing import EventDict, Processor, WrappedLogger

def add_trace_id(_: WrappedLogger, __: str, event_dict: EventDict) -> EventDict:
    span = trace.get_current_span().get_span_context()
    if span.is_valid:                                    # joins this log line to its trace
        event_dict["trace_id"] = format(span.trace_id, "032x")
    return event_dict

SHARED: list[Processor] = [
    structlog.contextvars.merge_contextvars,
    structlog.processors.add_log_level,
    structlog.processors.TimeStamper(fmt="iso", utc=True),
    add_trace_id,
]

def configure_logging(level: str = "INFO") -> None:
    structlog.configure(
        processors=[*SHARED, structlog.processors.format_exc_info, structlog.processors.JSONRenderer()],
        wrapper_class=structlog.make_filtering_bound_logger(logging.getLevelName(level)),
        cache_logger_on_first_use=True,
    )
    # stdlib loggers (uvicorn, sqlalchemy, httpx) go through the same processors: JSON, IDs included
    handler = logging.StreamHandler()
    handler.setFormatter(structlog.stdlib.ProcessorFormatter(
        foreign_pre_chain=SHARED,
        processors=[
            structlog.stdlib.ProcessorFormatter.remove_processors_meta,
            structlog.processors.JSONRenderer(),
        ],
    ))
    logging.basicConfig(handlers=[handler], level=level, force=True)
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        logging.getLogger(name).handlers.clear()         # uvicorn installs its own text handlers
        logging.getLogger(name).propagate = True
```

`configure_logging` runs in `create_app()`, which uvicorn calls (`--factory`) after installing its own
handlers, so the reset above wins. Get loggers with `structlog.get_logger()` per module. Never log secrets, tokens or personal data;
log identifiers instead of payloads.

## 2. Correlation IDs via contextvars
A middleware reads (or generates) `X-Request-ID`, binds it for the request's lifetime and echoes it back.
`contextvars` propagate across `await`, so no ID is passed by hand.

```python
_VALID_ID = re.compile(r"[A-Za-z0-9._-]{1,64}")   # client-supplied: never trust length or charset

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

The `add_trace_id` processor (section 1) adds the active `trace_id` to every line so logs and traces join.
Workers bind a job ID the same way.

## 3. Traces with OpenTelemetry
```python
def configure_tracing(service_name: str, otlp_endpoint: str, app: FastAPI) -> None:
    provider = TracerProvider(resource=Resource.create({"service.name": service_name}))
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=otlp_endpoint)))
    trace.set_tracer_provider(provider)
    FastAPIInstrumentor.instrument_app(app)
    HTTPXClientInstrumentor().instrument()
```
Auto-instrumentation covers inbound requests and outbound `httpx`; add manual spans only around
meaningful domain steps: `with tracer.start_as_current_span("checkout.charge"):`. Configure the
exporter endpoint from settings and make tracing a no-op when it is unset (tests, local).

## 4. Metrics with prometheus-client
Expose `/metrics`; keep label sets small and bounded. Never expose `/metrics` publicly without authentication or a network policy.

```python
REQUESTS = Counter("http_requests_total", "HTTP requests", ["method", "route", "status"])
LATENCY = Histogram("http_request_duration_seconds", "HTTP latency", ["method", "route"],
                    buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5))

class MetricsMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        status = 500                                     # stays 500 if the app raises
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

`create_app()` registers it with `app.add_middleware(MetricsMiddleware)` and exposes the registry with
`app.mount("/metrics", make_asgi_app())` (see `python-fastapi-conventions` §7). The router sets
`scope["route"]` while it handles the request, so the label is the route template.

Label with the route **template** (`/v1/orders/{order_id}`), never the raw path, a user ID or an
error message: unbounded labels exhaust memory. Domain metrics (`orders_created_total`) are recorded
by a small recorder class injected into the service, not by `Counter.inc()` scattered through logic.
Under multi-process servers set `PROMETHEUS_MULTIPROC_DIR` and use `MultiProcessCollector`.

## 5. What to measure
Rate, errors and duration per route (RED), dependency call latency and failures, queue depth for
workers, and one SLI per user-facing promise (e.g. 99% of `POST /v1/orders` under 500 ms).

## Do / Don't
- ✅ One log configuration, JSON to stdout; let the platform ship it.
- ✅ Bind IDs once in middleware; read them from contextvars.
- ✅ Use route templates and enumerated values as metric labels.
- ❌ `print()` or `logging.basicConfig` text logs in services.
- ❌ f-string log messages carrying variable data; use key/value fields.
- ❌ Logging a caught exception and re-raising it at every layer (log once, at the handler).
- ❌ High-cardinality labels (IDs, emails, raw URLs).

## Cross-references
- `python-fastapi-conventions` — where middleware is registered in `create_app()`.
- `python-error-handling` — the single place unexpected errors are logged.
- `python-ci` — container health checks and image setup.

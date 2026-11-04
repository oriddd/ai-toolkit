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
last_reviewed: 2026-11-03
---

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
def configure_logging(level: str = "INFO") -> None:
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(logging.getLevelName(level)),
        cache_logger_on_first_use=True,
    )
```

Get loggers with `structlog.get_logger()` per module. Never log secrets, tokens or personal data;
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
            return await self.app(scope, receive, send)
        headers = Headers(scope=scope)
        incoming = headers.get("x-request-id", "")
        request_id = incoming if _VALID_ID.fullmatch(incoming) else uuid4().hex   # bounded, safe to log and echo
        structlog.contextvars.clear_contextvars()
        structlog.contextvars.bind_contextvars(request_id=request_id)

        async def send_with_id(message: Message) -> None:
            if message["type"] == "http.response.start":
                MutableHeaders(scope=message)["x-request-id"] = request_id
            await send(message)

        await self.app(scope, receive, send_with_id)
```

Add the active `trace_id` to the log context so logs and traces join. Workers bind a job ID the same way.

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
```

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

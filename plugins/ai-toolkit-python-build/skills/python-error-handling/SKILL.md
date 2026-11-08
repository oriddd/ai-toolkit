---
name: python-error-handling
description: >
  Python / FastAPI error contract — typed exception hierarchy, error-code and message catalogue, ONE handler mapping
  errors to RFC 7807 problem+json. Use when raising, adding or mapping any exception or error response. For request
  validation use `python-input-validation`.
tier: must
applies_to: [rest, worker, cli, library]
depends_on: [python-code-structure]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

# Python Error Handling Skill
## When to use
Whenever business code needs to fail, or an exception must become an HTTP response.

## Layout

```
src/my_service/errors/
├── base.py            # DomainError root + category bases
├── codes.py           # ErrorCode catalogue (code, status, title, message template)
├── domain.py          # concrete errors: OrderNotFoundError, ...
└── problem.py         # ProblemDetail model
src/my_service/api/errors.py   # the one handler registration
```

## Dependencies
```toml
dependencies = ["fastapi>=0.115", "pydantic>=2.8"]
```

## 1. Typed hierarchy
A single root, a few category bases (one per HTTP meaning), and one concrete class per failure that a
caller might want to catch. Business code raises domain errors only; it knows nothing about HTTP.

```python
class DomainError(Exception):
    code: ClassVar[ErrorCode]  # set by every raised class; category bases are never raised directly

    def __init__(self, **params: object) -> None:
        self.params = params
        super().__init__(self.code.message.format_map(_Tolerant(params)))

class _Tolerant(dict[str, object]):
    def __missing__(self, key: str) -> str:  # raised without params (e.g. at commit): no KeyError
        return "<unknown>"

class NotFoundError(DomainError): ...
class ConflictError(DomainError): ...

class DependencyUnavailableError(DomainError):
    code = ErrorCodes.DEPENDENCY_UNAVAILABLE

class OrderNotFoundError(NotFoundError):
    code = ErrorCodes.ORDER_NOT_FOUND

class OrderVersionConflictError(ConflictError):
    code = ErrorCodes.ORDER_VERSION_CONFLICT
```

## 2. Message catalogue
All codes, statuses and texts live in one module. No string literals at raise sites.

```python
@dataclass(frozen=True, slots=True)
class ErrorCode:
    code: str          # stable, machine-readable: "ORDER_NOT_FOUND"
    status: int
    title: str
    message: str       # str.format template

class ErrorCodes:
    ORDER_NOT_FOUND = ErrorCode(
        "ORDER_NOT_FOUND", 404, "Order not found", "Order {order_id} does not exist")
    ORDER_ALREADY_EXISTS = ErrorCode(
        "ORDER_ALREADY_EXISTS", 409, "Order already exists", "Order {order_id} already exists")
    ORDER_VERSION_CONFLICT = ErrorCode(
        "ORDER_VERSION_CONFLICT", 409, "Version conflict", "Order {order_id} was modified concurrently")
    EMAIL_ALREADY_REGISTERED = ErrorCode(  # no email in the text: it would reach body and logs
        "EMAIL_ALREADY_REGISTERED", 409, "Email already registered", "This email is already registered")
    DEPENDENCY_UNAVAILABLE = ErrorCode(
        "DEPENDENCY_UNAVAILABLE", 503, "Dependency unavailable", "Dependency {dependency} is unavailable")
```

Raise: `raise OrderNotFoundError(order_id=order_id)`. Codes are an API; never rename a released one.

## 3. Problem model
```python
class FieldError(BaseModel):
    field: str         # wire path: location + JSON key as sent, "body.customer_email"
    code: str          # pydantic error type: "string_too_short"
    message: str

class ProblemDetail(BaseModel):
    type: str = "about:blank"
    title: str
    status: int
    detail: str
    code: str
    instance: str | None = None
    errors: list[FieldError] | None = None
```

## 4. One handler, one place
Registered once from `create_app()`. It maps the catalogue entry to the response; adding an error
never requires touching the handler. Framework errors (unknown route -> 404, wrong method -> 405) are
Starlette `HTTPException`s raised before any router runs, so they get their own handler: without it
they would leave as `{"detail": ...}` and "every non-2xx body is problem+json" would be false.

```python
from collections.abc import Mapping
from http import HTTPStatus

import structlog
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = structlog.get_logger()

def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(DomainError)
    async def domain_error(request: Request, exc: DomainError) -> JSONResponse:
        return _problem(request, status_code=exc.code.status, title=exc.code.title,
                        detail=str(exc), code=exc.code.code)

    @app.exception_handler(RequestValidationError)
    async def invalid_request(request: Request, exc: RequestValidationError) -> JSONResponse:
        return _problem(request, status_code=422, title="Validation failed",
                        detail="Request is invalid", code="VALIDATION_FAILED", errors=field_errors(exc))

    @app.exception_handler(StarletteHTTPException)  # starlette.exceptions.HTTPException: 404, 405
    async def http_error(request: Request, exc: StarletteHTTPException) -> JSONResponse:
        try:
            title = HTTPStatus(exc.status_code).phrase
        except ValueError:                             # non-standard code (e.g. 499)
            title = "HTTP error"
        # routers never raise HTTPException, so exc.detail is framework text ("Not Found",
        # "Method Not Allowed", "Not authenticated"): safe to pass on
        return _problem(request, status_code=exc.status_code, title=title, detail=str(exc.detail),
                        code=f"HTTP_{exc.status_code}", headers=exc.headers)

    @app.exception_handler(Exception)
    async def unexpected(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("unhandled_error")
        return _problem(request, status_code=500, title="Internal error",
                        detail="Unexpected error", code="INTERNAL_ERROR")

def field_errors(exc: RequestValidationError) -> list[FieldError]:
    # loc/type/msg only: exc.errors() also has the rejected `input` (see python-input-validation)
    return [
        FieldError(field=".".join(str(part) for part in err["loc"]), code=err["type"], message=err["msg"])
        for err in exc.errors()
    ]

def _problem(
    request: Request,
    *,                                  # keyword-only: seven same-typed arguments are easy to swap
    status_code: int,
    title: str,
    detail: str,
    code: str,
    errors: list[FieldError] | None = None,
    headers: Mapping[str, str] | None = None,
) -> JSONResponse:
    body = ProblemDetail(title=title, status=status_code, detail=detail, code=code,
                         instance=str(request.url.path), errors=errors)
    return JSONResponse(body.model_dump(exclude_none=True), status_code=status_code,
                        media_type="application/problem+json", headers=dict(headers or {}))
```

The 500 body never leaks exception text or stack traces; those go to the log. Starlette still
re-raises after the 500 handler runs, so test clients need `raise_server_exceptions=False` to see the body.

The `Exception` handler is run by Starlette's `ServerErrorMiddleware`, which sits **outside** every
middleware added with `add_middleware`. The 500 response therefore has no `x-request-id` and no CORS
headers (the log line still has the request ID, bound in contextvars before the failure). If clients need
them on a 500, wrap the whole app in an outer ASGI middleware that catches the exception and builds the
response itself.

`field` is the wire path: the location (`body`, `query`, `path`) plus the JSON key exactly as the client sent
it (`body.customer_email`, snake_case unless the model declares aliases). Clients strip the location prefix
and map wire names to their own form fields (see `react-native-input-validation`).

`msg` is pydantic's developer text, and for some error types it quotes part of the rejected value
(`uuid_parsing`: "invalid character: expected ... found `x`"). For fields that may carry sensitive data,
replace `msg` with catalogue text keyed by `type`, or drop it; clients branch on `code`, never on `message`.

## 5. Translate at the boundary, keep the cause
Clients and repositories catch library exceptions and re-raise domain errors with `from`:

```python
try:
    response = await self._http.get(url)
except httpx.TransportError as exc:               # timeout, refused, DNS: dependency unreachable
    raise DependencyUnavailableError(dependency="billing") from exc
if response.is_server_error:                      # 5xx: unavailable, may be retried
    raise DependencyUnavailableError(dependency="billing")
if response.status_code == HTTPStatus.NOT_FOUND:  # each documented 4xx: its own domain error
    raise InvoiceNotFoundError(invoice_id=invoice_id)
response.raise_for_status()                       # any other 4xx is our bug: 500, not 503
```

Only transport failures and 5xx mean "unavailable" (503); a 4xx is an answer from a working dependency
and becomes a domain error (or a 500 when it means our request was wrong).

## 6. Catch narrowly
Catch only where you can recover or translate. No `except Exception: pass`; no `except Exception` that
returns `None`. Let everything else bubble to the handler.

## Do / Don't
- ✅ One concrete error class per catchable failure, parameters as keyword arguments.
- ✅ Stable `code` in every response so clients branch on it, not on text.
- ✅ Test the mapping: error raised -> status, `code`, media type (see `python-unit-tests`).
- ❌ `raise HTTPException(...)` or `raise ValueError("...")` in services.
- ❌ Inline message strings or status ints at raise sites.
- ❌ `try/except` in routers to build responses; a second exception handler for the same type.
- ❌ Returning `None`/`-1`/error tuples to signal failure.

## Cross-references
- `python-fastapi-conventions` — problem+json as the API error shape.
- `python-input-validation` — produces the 422 `errors` list.
- `python-persistence` — raises `ConflictError` on optimistic-lock failure.
- `python-observability` — logging the unexpected-error path with correlation IDs.

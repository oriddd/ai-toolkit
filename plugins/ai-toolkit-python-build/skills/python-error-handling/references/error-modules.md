# python-error-handling — the error modules

Back to [`SKILL.md`](../SKILL.md) §1 to §4. The catalogue, the hierarchy, the concrete errors, the problem model and
the handler registration, as files. `InsufficientCreditError` is raised by the validation rule of
`python-input-validation` §4.

## Catalogue and hierarchy

### `src/my_service/errors/codes.py`

```python
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class ErrorCode:
    code: str
    status: int
    title: str
    message: str


class ErrorCodes:
    ORDER_NOT_FOUND = ErrorCode(
        "ORDER_NOT_FOUND", 404, "Order not found", "Order {order_id} does not exist"
    )
    ORDER_ALREADY_EXISTS = ErrorCode(
        "ORDER_ALREADY_EXISTS", 409, "Order already exists", "Order {order_id} already exists"
    )
    ORDER_VERSION_CONFLICT = ErrorCode(
        "ORDER_VERSION_CONFLICT",
        409,
        "Version conflict",
        "Order {order_id} was modified concurrently",
    )
    CUSTOMER_NOT_FOUND = ErrorCode(
        "CUSTOMER_NOT_FOUND", 404, "Customer not found", "Customer {customer_id} does not exist"
    )
    INSUFFICIENT_CREDIT = ErrorCode(
        "INSUFFICIENT_CREDIT",
        409,
        "Insufficient credit",
        "Customer {customer_id} has insufficient credit",
    )
    DEPENDENCY_UNAVAILABLE = ErrorCode(
        "DEPENDENCY_UNAVAILABLE",
        503,
        "Dependency unavailable",
        "Dependency {dependency} is unavailable",
    )
    DEPENDENCY_BAD_RESPONSE = ErrorCode(
        "DEPENDENCY_BAD_RESPONSE",
        502,
        "Bad dependency response",
        "Dependency {dependency} sent an invalid response",
    )
    NOT_AUTHENTICATED = ErrorCode(
        "NOT_AUTHENTICATED", 401, "Not authenticated", "A valid bearer token is required"
    )
    FORBIDDEN = ErrorCode("FORBIDDEN", 403, "Forbidden", "The caller may not perform this action")
```

### `src/my_service/errors/base.py`

```python
from collections.abc import Mapping
from typing import ClassVar

from my_service.errors.codes import ErrorCode, ErrorCodes


class _Tolerant(dict[str, object]):
    def __missing__(self, key: str) -> str:
        return "<unknown>"


class DomainError(Exception):
    code: ClassVar[ErrorCode]
    headers: ClassVar[Mapping[str, str]] = {}

    def __init__(self, **params: object) -> None:
        self.params = params
        super().__init__(self.code.message.format_map(_Tolerant(params)))


class NotFoundError(DomainError): ...


class ConflictError(DomainError): ...


class ForbiddenError(DomainError): ...


class UnauthorizedError(DomainError):
    headers: ClassVar[Mapping[str, str]] = {"WWW-Authenticate": "Bearer"}


class DependencyUnavailableError(DomainError):
    code = ErrorCodes.DEPENDENCY_UNAVAILABLE


class DependencyBadResponseError(DomainError):
    code = ErrorCodes.DEPENDENCY_BAD_RESPONSE


class NotAuthenticatedError(UnauthorizedError):
    code = ErrorCodes.NOT_AUTHENTICATED


class AccessDeniedError(ForbiddenError):
    code = ErrorCodes.FORBIDDEN
```

## Concrete errors and the problem model

### `src/my_service/errors/domain.py`

```python
from my_service.errors.base import ConflictError, NotFoundError
from my_service.errors.codes import ErrorCodes


class OrderNotFoundError(NotFoundError):
    code = ErrorCodes.ORDER_NOT_FOUND


class OrderAlreadyExistsError(ConflictError):
    code = ErrorCodes.ORDER_ALREADY_EXISTS


class OrderVersionConflictError(ConflictError):
    code = ErrorCodes.ORDER_VERSION_CONFLICT


class CustomerNotFoundError(NotFoundError):
    code = ErrorCodes.CUSTOMER_NOT_FOUND


class InsufficientCreditError(ConflictError):
    code = ErrorCodes.INSUFFICIENT_CREDIT
```

### `src/my_service/errors/problem.py`

```python
from pydantic import BaseModel


class FieldError(BaseModel):
    field: str
    code: str
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

## Handlers

### `src/my_service/api/errors.py`

```python
from collections.abc import Mapping
from http import HTTPStatus

import structlog
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from my_service.errors.base import DomainError
from my_service.errors.problem import FieldError, ProblemDetail

logger = structlog.get_logger()


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(DomainError)
    async def domain_error(request: Request, exc: DomainError) -> JSONResponse:
        return _problem(
            request,
            status_code=exc.code.status,
            title=exc.code.title,
            detail=str(exc),
            code=exc.code.code,
            headers=exc.headers,
        )

    @app.exception_handler(RequestValidationError)
    async def invalid_request(request: Request, exc: RequestValidationError) -> JSONResponse:
        return _problem(
            request,
            status_code=422,
            title="Validation failed",
            detail="Request is invalid",
            code="VALIDATION_FAILED",
            errors=field_errors(exc),
        )

    @app.exception_handler(StarletteHTTPException)  # starlette.exceptions.HTTPException: 404, 405
    async def http_error(request: Request, exc: StarletteHTTPException) -> JSONResponse:
        try:
            title = HTTPStatus(exc.status_code).phrase
        except ValueError:  # non-standard code (e.g. 499)
            title = "HTTP error"
        # routers never raise HTTPException, so exc.detail is framework text ("Not Found",
        # "Method Not Allowed", "Not authenticated"): safe to pass on
        return _problem(
            request,
            status_code=exc.status_code,
            title=title,
            detail=str(exc.detail),
            code=f"HTTP_{exc.status_code}",
            headers=exc.headers,
        )

    @app.exception_handler(Exception)
    async def unexpected(request: Request, exc: Exception) -> JSONResponse:
        logger.exception("unhandled_error")
        return _problem(
            request,
            status_code=500,
            title="Internal error",
            detail="Unexpected error",
            code="INTERNAL_ERROR",
        )


def field_errors(exc: RequestValidationError) -> list[FieldError]:
    # loc/type/msg only: exc.errors() also has the rejected `input` (see python-input-validation)
    return [
        FieldError(
            field=".".join(str(part) for part in err["loc"]), code=err["type"], message=err["msg"]
        )
        for err in exc.errors()
    ]


def _problem(
    request: Request,
    *,  # keyword-only: seven same-typed arguments are easy to swap
    status_code: int,
    title: str,
    detail: str,
    code: str,
    errors: list[FieldError] | None = None,
    headers: Mapping[str, str] | None = None,
) -> JSONResponse:
    body = ProblemDetail(
        title=title,
        status=status_code,
        detail=detail,
        code=code,
        instance=str(request.url.path),
        errors=errors,
    )
    return JSONResponse(
        body.model_dump(exclude_none=True),
        status_code=status_code,
        media_type="application/problem+json",
        headers=dict(headers or {}),
    )
```

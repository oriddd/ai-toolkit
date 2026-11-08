---
name: python-input-validation
description: >
  Python input validation with pydantic v2 — Field constraints and validated types, model validators for cross-field
  rules, injectable rule objects, custom messages. Use when adding or changing any validation rule; never ad-hoc
  if/raise guards in routers or services.
tier: must
applies_to: [rest, worker, cli]
depends_on: [python-code-structure, python-error-handling]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

# Python Input Validation Skill
## When to use
Whenever a rule decides whether input is acceptable: a format, a range, a relation between fields, or a
check against existing data.

## Layout

```
src/my_service/
├── models/
│   ├── requests.py        # CreateOrderRequest: field + cross-field rules
│   └── types.py           # reusable validated types: Email, PositiveCents
└── validation/
    ├── rules.py           # Rule Protocol + rules that need collaborators
    └── order_validator.py # composes rules for one use case
```

## Dependencies
```toml
dependencies = ["pydantic>=2.8", "email-validator>=2.2"]
```

## 1. Where validation lives
Three tiers, each owning one kind of rule. Nothing else validates.

| Rule kind | Owner |
| --- | --- |
| Shape of one field (type, range, regex, length) | pydantic `Field` / `Annotated` types |
| Relation between fields of one payload | `@model_validator(mode="after")` |
| Needs data or a collaborator (uniqueness, existence, quota) | an injected rule object, called by the operation |

## 2. Field rules: reusable validated types
Define each constraint once as a type and reuse it.

```python
Email = Annotated[EmailStr, StringConstraints(max_length=254, to_lower=True)]
PositiveCents = Annotated[int, Field(gt=0, le=100_000_000, description="Amount in cents")]

class CreateOrderRequest(BaseModel):
    model_config = ConfigDict(frozen=True, extra="forbid")

    customer_email: Email
    total_cents: PositiveCents
    coupon: str | None = Field(default=None, pattern=r"^[A-Z0-9]{6,12}$")
```

`extra="forbid"` rejects unknown fields; models are frozen so validated data cannot drift.

## 3. Cross-field rules
```python
class DateRange(BaseModel):
    start: date
    end: date

    @model_validator(mode="after")
    def end_not_before_start(self) -> Self:
        if self.end < self.start:
            raise ValueError("end must not be before start")
        return self
```

Validators are pure: no I/O, no clock, no database. Use `@field_validator` for normalising one field.

## 4. Rules that need collaborators: injectable rule objects
```python
class Rule[T](Protocol):
    async def check(self, value: T) -> None: ...      # raises a DomainError

class EmailAlreadyRegisteredError(ConflictError):
    code = ErrorCodes.EMAIL_ALREADY_REGISTERED          # catalogue entry: see `python-error-handling`

class EmailNotRegisteredRule:
    def __init__(self, users: UserRepository) -> None:
        self._users = users

    async def check(self, email: str) -> None:
        if await self._users.exists_by_email(email):
            raise EmailAlreadyRegisteredError()          # no email param: it would reach `detail` and the logs
```

A "this email is taken" answer tells anyone probing the endpoint which addresses have accounts
(account enumeration). On a public sign-up endpoint, prefer a uniform response ("check your inbox") and
tell the owner by email; keep the 409 only where the caller is already authenticated or the risk is accepted.

The operation receives the rules through its constructor and calls them before acting; the rule raises
a typed error from the catalogue (see `python-error-handling`). Compose with a small validator class
holding `list[Rule[T]]` when several apply.

## 5. Custom messages
Pydantic messages are for developers; clients get stable codes. In the exception handler, map
`ValidationError` entries to `{field, code, message}` using `err["loc"]` and `err["type"]`, and write
validator messages for humans ("end must not be before start"). Never put values that may be sensitive
into messages.

The rejected value is also in the error structure: `hide_input_in_errors=True` only removes it from
`str(exc)`; `exc.errors()` and `exc.json()` still contain `input`, and **FastAPI's default 422 body
echoes it** (a too-short password comes straight back). Build the body from `loc` / `type` / `msg` only
(the handler in `python-error-handling` does), or for a plain pydantic `ValidationError` in a worker/CLI
call `exc.errors(include_input=False)` / `exc.json(include_input=False)`. FastAPI's `RequestValidationError.errors()`
does not accept `include_input`, so pick the three keys yourself.

## 6. Same models outside HTTP
Workers and CLIs validate with the same models: `CreateOrderRequest.model_validate_json(payload)` at the
boundary, then pass the typed object inward. Past the boundary, code trusts its types.

## Do / Don't
- ✅ One reusable `Annotated` type per constraint; one model per payload.
- ✅ Keep model validators pure; put data-dependent checks in rule objects.
- ✅ Test each rule with valid, invalid and boundary values via `parametrize` (see `python-unit-tests`).
- ❌ `if not x: raise ValueError` inside routers, operations or services for user input.
- ❌ Database or HTTP calls inside pydantic validators.
- ❌ Accepting `dict` / `Any` payloads and validating by hand.
- ❌ Duplicating a rule in the model and in the service.

## Cross-references
- `python-error-handling` — the 422 problem+json body and typed errors raised by rules.
- `python-fastapi-conventions` — request/response model conventions.
- `python-code-structure` — injecting rule objects.
- `python-unit-tests` — table-driven validation tests.

---
name: python-code-structure
description: >
  Python 3.12 service layout — src layout, api/operations/services/clients/models/config layers, pydantic-settings,
  constructor injection, one-way dependencies. Use before creating or editing ANY Python module, package, service or
  use case in a FastAPI, worker or CLI service.
tier: must
applies_to: [rest, worker, cli, library]
depends_on: []
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-11
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# Python Code Structure Skill
## When to use
Whenever you create a Python service, add a feature, or touch more than one module: it defines the
package layout, the dependency direction and how collaborators are wired.

## 1. Canonical layout

```
my-service/
├── pyproject.toml
├── src/my_service/              # src layout: tests can never import the working tree by accident
│   ├── main.py                  # create_app() + lifespan: the composition root
│   ├── api/                     # FastAPI routers + dependencies: HTTP <-> model translation only
│   ├── operations/              # one class/function per use case: orchestrates services
│   ├── services/                # one domain capability each: business rules, no HTTP types
│   ├── clients/                 # outbound transport (httpx, SDKs) behind a Protocol (see `python-external-client`)
│   ├── repositories/            # persistence behind a Protocol (see `python-persistence`)
│   ├── messaging/               # outbox relay, event publisher, consumers (see `python-messaging`)
│   ├── security/                # token verification behind a Protocol (see `python-security`)
│   ├── models/                  # pydantic request/response models + domain value objects
│   ├── errors/                  # exception hierarchy + message catalogue (see `python-error-handling`)
│   └── config/                  # pydantic-settings classes
└── tests/                       # mirrors src/ one-to-one (see `python-unit-tests`)
```

Create only the packages you need; never scaffold empty ones. A growing service may group by feature
(`orders/api`, `orders/services`, ...) with the same layer names inside each feature.

## 2. Dependency direction

```
api ──► operations ──► services ──► repositories / clients
 │           │             │
 └───────────┴─────────────┴──► models, errors, config   (leaf packages, import nothing above them)
```

- A layer imports only from layers to its right. `services` never import `fastapi`; `models` never import `services`.
- Enforce it mechanically with an `import-linter` `layers` contract (see `python-static-analysis` §3); ruff's
  `TID` rules only ban specific named imports, they cannot express layer direction.
- `clients/`, `repositories/`, `messaging/` and `security/` are adapters at the right-hand end: they may import
  the leaf packages (and `messaging/` the repositories), never `services/`, `operations/` or `api/`.
- No cycles; if two modules need each other, extract the shared piece into a third brick.

## 3. The LEGO brick principle
Each module/class is small (class ≤ ~100 lines, function ≤ ~30 lines), has one reason to change and a
name that makes comments unnecessary: `InvoiceTotalCalculator`, `UserEmailUniquenessRule`.
A section comment such as `# --- validation ---` inside a class marks a missing brick: extract it.

## 4. Depend on abstractions, wire by injection
Collaborators are declared as `Protocol`s and received through the constructor. No module-level
singletons, no `import` of a concrete client inside a service.

```python
from dataclasses import dataclass
from datetime import datetime
from typing import Protocol

class Clock(Protocol):                       # services/clock.py
    def now(self) -> datetime: ...

class PaymentGateway(Protocol):
    async def charge(self, customer_id: str, cents: int) -> str: ...

@dataclass(frozen=True, slots=True)
class Receipt:                               # models/receipt.py
    charge_id: str
    paid_at: datetime

class CheckoutService:
    def __init__(self, gateway: PaymentGateway, clock: Clock) -> None:
        self._gateway = gateway
        self._clock = clock

    async def checkout(self, order: Order) -> Receipt:
        charge_id = await self._gateway.charge(order.customer_id, order.total_cents)
        return Receipt(charge_id=charge_id, paid_at=self._clock.now())
```

`Order` is the frozen domain model from `models/order.py` (`id`, `customer_id`, `total_cents`, `status`,
`version`; see `python-persistence`).

Time, randomness, UUIDs and the environment are collaborators too (`Clock`, `IdGenerator`), never
`datetime.now()` buried in logic. Wiring happens only in the composition root (`main.py`) and FastAPI
`Depends` providers (see `python-fastapi-conventions`).

## 5. Settings via pydantic-settings
One typed, immutable settings class per concern; read the environment once, at startup.

```python
from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import URL, make_url

class DatabaseSettings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="DB_", frozen=True)

    url: str                     # postgresql+asyncpg://app@db:5432/orders, without the password
    password: SecretStr
    pool_size: int = 10

    def sqlalchemy_url(self) -> URL:     # the one place the secret joins the URL
        return make_url(self.url).set(password=self.password.get_secret_value())

class AppSettings(BaseSettings):         # the composition root reads this once: create_app(settings)
    model_config = SettingsConfigDict(frozen=True)

    db: DatabaseSettings = Field(default_factory=DatabaseSettings)
```

Inject the settings object into whoever needs it; business code never touches `os.environ`.
Secrets use `SecretStr`. Tests construct settings explicitly: `DatabaseSettings(url=..., password=...)`.
Keyword arguments win over the environment, but fields you omit (`pool_size`) are still read from `DB_*`
variables (and `.env` when `env_file` is set). For a hermetic test, use a test-only subclass that reads nothing else:

```python
from pydantic_settings import PydanticBaseSettingsSource

class IsolatedDatabaseSettings(DatabaseSettings):    # tests/: constructor arguments only
    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: type[BaseSettings],
        init_settings: PydanticBaseSettingsSource,
        env_settings: PydanticBaseSettingsSource,       # pydantic-settings passes all sources by keyword
        dotenv_settings: PydanticBaseSettingsSource,
        file_secret_settings: PydanticBaseSettingsSource,
    ) -> tuple[PydanticBaseSettingsSource, ...]:
        return (init_settings,)
```

## 6. Naming
- Modules are `snake_case` nouns for what they hold: `invoice_total_calculator.py`, not `utils.py` / `helpers.py` / `common.py`.
- Suffixes carry meaning: `*Service`, `*Client`, `*Repository`, `*Operation`, `*Rule`, `*Settings`, `*Error`.
- Public functions have full type hints. Add `from __future__ import annotations` only where a forward
  reference needs it (lazy annotations by default arrive with PEP 649 in 3.14, not 3.12); avoid it in FastAPI
  and pydantic modules, which resolve annotations at runtime.
- Immutable data: `@dataclass(frozen=True, slots=True)` or a frozen pydantic model.

## 7. Smallest pattern that fits
A one-endpoint service needs a router, one service and a model, not seven layers. Add `operations/`
only when a use case orchestrates several services; add a strategy registry only when behaviour is
chosen at runtime among 3+ implementations. A plain function beats a class with one method and no state.

## Do / Don't
- ✅ Inject `Protocol`-typed collaborators through `__init__`; build the graph in `main.py`.
- ✅ Keep `api/` thin: parse, call one operation, return a model.
- ✅ Use frozen models/dataclasses for data crossing layers.
- ❌ `utils.py` / `helpers.py` grab-bags, or `from x import *`.
- ❌ Reading `os.environ`, calling `datetime.now()` or constructing `httpx.Client()` inside services.
- ❌ Module-level mutable state or singletons; mutable default arguments.
- ❌ Business rules in routers, or `fastapi` imports in `services/`.

## Cross-references
- `python-fastapi-conventions` — the `api/` layer in detail.
- `python-error-handling`, `python-input-validation`, `python-persistence`, `python-external-client`,
  `python-security`, `python-messaging` — the build-phase bricks.
- `python-unit-tests` — how each brick is tested with fakes.
- `python-static-analysis` — enforcing import direction and typing.

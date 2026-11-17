# python-code-structure — project skeleton and shared modules

Back to [`SKILL.md`](../SKILL.md) §1b and §5. These files are the starting point of a service: the complete
`pyproject.toml` (the union of every Python skill's dependency list and tool table; keep only the groups your service
uses), the settings classes, the sample domain model and the injected clock and id generator. Every directory under
`src/my_service/` and `tests/` is a package: it has an empty `__init__.py`.

The sample domain is one aggregate, `Order` (`id`, `customer_id`, `total_cents`, `status`, `version`). `version`
defaults to `1`, so a new order is built with four arguments and the repository returns the stored version.
`tools/render-python-proof.sh` in the toolkit repository renders every file below into a fresh `uv init` project and
runs the whole verify sequence on it.

## Project file

### `pyproject.toml`

```toml
[project]
name = "my-service"
version = "0.1.0"
description = "Orders service built from the ai-toolkit Python skills"
readme = "README.md"
requires-python = ">=3.14"
dependencies = [
  "fastapi>=0.115",
  "uvicorn[standard]>=0.30",
  "pydantic>=2.8",
  "pydantic-settings>=2.4",
  "email-validator>=2.2",
  "sqlalchemy[asyncio]>=2.0.30",
  "asyncpg>=0.29",
  "alembic>=1.13",
  "aiokafka>=0.11",
  "redis>=5.0",
  "structlog>=24.4",
  "prometheus-client>=0.20",
  "opentelemetry-sdk>=1.27",
  "opentelemetry-exporter-otlp>=1.27",
  "opentelemetry-instrumentation-fastapi>=0.48b0",
  "opentelemetry-instrumentation-httpx>=0.48b0",
  "httpx>=0.28",
  "tenacity>=9.0",
  "pyjwt[crypto]>=2.10",
  "cryptography>=43",
  "apscheduler>=3.10,<4",
]

[project.scripts]
my-service-worker = "my_service.worker:main"
my-service-job = "my_service.jobs:main"

[build-system]
requires = ["uv_build>=0.13.7,<0.14.0"]
build-backend = "uv_build"

[dependency-groups]
dev = [
  "ruff>=0.12",
  "mypy>=1.11",
  "pre-commit>=3.8",
  "import-linter>=2.0",
  "pytest>=8.3",
  "pytest-asyncio>=0.26",
  "pytest-cov>=5.0",
  "asgi-lifespan>=2.1",
  "respx>=0.22",
  "testcontainers[postgres,redis]>=4.15",
  "types-docker",
  "diff-cover>=9.0",
  "pip-audit>=2.7",
]

[tool.ruff]
line-length = 100
target-version = "py314"
src = ["src", "tests"]

[tool.ruff.lint]
select = [
  "E", "F", "W", "I",
  "B", "BLE",
  "UP", "SIM", "C4",
  "ASYNC", "S",
  "PL", "RET", "TID",
  "ANN", "T20", "DTZ",
  "N",
  "PGH", "RUF",
]
ignore = ["PLR0913"]

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["S101", "PLR2004", "N802"]

[tool.mypy]
python_version = "3.14"
strict = true
plugins = ["pydantic.mypy"]
warn_unreachable = true
files = ["src", "tests"]
mypy_path = "src"

[[tool.mypy.overrides]]
module = ["aiokafka", "aiokafka.*", "apscheduler", "apscheduler.*"]
ignore_missing_imports = true

[tool.importlinter]
root_package = "my_service"
include_external_packages = true

[[tool.importlinter.contracts]]
name = "services do not import the api layer or fastapi"
type = "forbidden"
source_modules = ["my_service.services", "my_service.operations", "my_service.validation"]
forbidden_modules = ["my_service.api", "fastapi"]

[[tool.importlinter.contracts]]
name = "layers point one way"
type = "layers"
containers = ["my_service"]
layers = [
  "api",
  "(operations)",
  "(services)",
  "(validation)",
  "(repositories) | (clients)",
  "(models)",
  "(errors) | (config)",
]

[tool.pytest.ini_options]
asyncio_mode = "auto"
asyncio_default_fixture_loop_scope = "session"
asyncio_default_test_loop_scope = "session"
addopts = "--strict-markers"
markers = ["integration: needs real infrastructure (see python-integration-tests)"]
testpaths = ["tests"]

[tool.coverage.run]
source = ["my_service"]
branch = true

[tool.coverage.report]
fail_under = 85
exclude_also = ["if TYPE_CHECKING:", "^\\s*\\.\\.\\.$"]
```

## Settings

### `src/my_service/config/settings.py`

```python
from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import URL, make_url


class DatabaseSettings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="DB_", frozen=True)

    url: str
    password: SecretStr
    pool_size: int = 10

    def sqlalchemy_url(self) -> URL:
        return make_url(self.url).set(password=self.password.get_secret_value())


class KafkaSettings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="KAFKA_", frozen=True)

    bootstrap_servers: str = "localhost:9092"
    group_id: str = "my-service"
    topics: list[str] = ["orders.order-placed.v1"]


class BillingSettings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="BILLING_", frozen=True)

    base_url: str = "http://billing"
    api_key: SecretStr = SecretStr("unused")
    read_timeout_seconds: float = 5.0
    connect_timeout_seconds: float = 2.0
    attempts: int = 3


class AuthSettings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="AUTH_", frozen=True)

    jwks_url: str = "http://localhost:8080/.well-known/jwks.json"
    issuer: str = "http://localhost:8080"
    audience: str = "my-service"


class AppSettings(BaseSettings):
    model_config = SettingsConfigDict(frozen=True)

    db: DatabaseSettings = Field(default_factory=DatabaseSettings)
    kafka: KafkaSettings = Field(default_factory=KafkaSettings)
    billing: BillingSettings = Field(default_factory=BillingSettings)
    auth: AuthSettings = Field(default_factory=AuthSettings)
    redis_url: str = "redis://localhost:6379"
    otlp_endpoint: str | None = Field(default=None, validation_alias="OTEL_EXPORTER_OTLP_ENDPOINT")
    metrics_port: int = 9090
    drain_seconds: float = 20.0
    relay_idle_seconds: float = 1.0
    expose_docs: bool = False
    cors_origins: list[str] = []
```

## Domain model and response model

### `src/my_service/models/order.py`

```python
from dataclasses import dataclass, replace
from uuid import UUID


@dataclass(frozen=True, slots=True)
class Order:
    id: UUID
    customer_id: str
    total_cents: int
    status: str
    version: int = 1

    def pay(self) -> Order:
        return replace(self, status="paid")
```

### `src/my_service/models/responses.py`

```python
from uuid import UUID

from pydantic import BaseModel


class OrderResponse(BaseModel):
    id: UUID
    status: str
    version: int
```

## Injected time and ids

### `src/my_service/services/clock.py`

```python
from datetime import UTC, datetime
from typing import Protocol


class Clock(Protocol):
    def now(self) -> datetime: ...


class SystemClock:
    def now(self) -> datetime:
        return datetime.now(UTC)
```

### `src/my_service/services/ids.py`

```python
from typing import Protocol
from uuid import UUID, uuid4


class IdGenerator(Protocol):
    def new_id(self) -> UUID: ...


class RandomIds:
    def new_id(self) -> UUID:
        return uuid4()
```

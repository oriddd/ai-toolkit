# python-security — PII, retention and erasure

Back to [`SKILL.md`](../SKILL.md) §7. The Python counterpart of the Java `data-privacy` skill: identify PII, keep
it out of logs, encrypt the sensitive columns, delete on schedule, and anonymise on request. Everything below ran
against PostgreSQL (testcontainers).

## 1. Masking in logs: one structlog processor
Put `mask_pii` last in the shared processor chain (`python-observability` §1) so it also covers stdlib loggers
(uvicorn's access log prints `?customer_id=<email>`):

### `src/my_service/observability/pii_masking.py`

```python
import re

from structlog.typing import EventDict, WrappedLogger

SENSITIVE_KEYS = frozenset(
    {"email", "phone", "name", "first_name", "last_name", "address", "ip", "ssn", "customer_email"}
)
EMAIL_PATTERN = re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")


def mask_value(value: str) -> str:
    return value[:1] + "***" if value else value


def _mask(value: object) -> object:
    if isinstance(value, str):
        return EMAIL_PATTERN.sub(lambda match: mask_value(match.group()), value)
    if isinstance(value, dict):
        return {key: _mask_entry(str(key), item) for key, item in value.items()}
    if isinstance(value, list | tuple):
        return [_mask(item) for item in value]
    return value


def _mask_entry(key: str, value: object) -> object:
    if key.lower() in SENSITIVE_KEYS and value is not None:
        return mask_value(str(value))
    return _mask(value)


def mask_pii(_: WrappedLogger, __: str, event_dict: EventDict) -> EventDict:
    return {key: _mask_entry(key, value) for key, value in event_dict.items()}
```

It masks values under known PII keys (recursively) and any e-mail address inside any string, including the event
message. Keep nothing that identifies the person (first character plus `***`, never a suffix).

Keep PII out of `repr` too, the Python equivalent of a `toString()` without PII:

```python
# models/requests.py: repr(request), and so any log of it, omits the field
customer_email: Email = Field(repr=False)
```

```python
def test_logging_structlogAndStdlibAccessLog_neverEmitRawEmail(
    capsys: pytest.CaptureFixture[str],
) -> None:
    configure_logging()
    structlog.get_logger().info("customer_seen", email="jane@example.com")
    access = logging.getLogger("uvicorn.access")
    access.info("GET /v1/orders?customer_id=jane@example.com 200")
    captured = capsys.readouterr()
    assert "jane@example.com" not in captured.out + captured.err
```
Full unit tests: `tests/unit/test_pii_masking.py` (nested dicts and lists, `None`, non-strings, the stdlib path, `repr`).

## 2. Field-level encryption: AES-256-GCM with key versions and a blind index
### `src/my_service/repositories/encrypted_type.py`

```python
import base64
import hashlib
import hmac
import os
from dataclasses import dataclass

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from sqlalchemy import String
from sqlalchemy.engine import Dialect
from sqlalchemy.types import TypeDecorator

NONCE_BYTES = 12


@dataclass(frozen=True)
class KeyRing:
    keys: tuple[tuple[int, bytes], ...]
    current: int

    def key(self, version: int) -> bytes:
        return dict(self.keys)[version]


class EncryptedString(TypeDecorator[str]):
    impl = String
    cache_ok = True

    def __init__(self, keyring: KeyRing) -> None:
        super().__init__()
        self._keyring = keyring

    def process_bind_param(self, value: str | None, dialect: Dialect) -> str | None:
        if value is None:
            return None
        nonce = os.urandom(NONCE_BYTES)
        sealed = AESGCM(self._keyring.key(self._keyring.current)).encrypt(
            nonce, value.encode(), None
        )
        return f"{self._keyring.current}:{base64.b64encode(nonce + sealed).decode()}"

    def process_result_value(self, value: str | None, dialect: Dialect) -> str | None:
        if value is None:
            return None
        version, _, encoded = value.partition(":")
        raw = base64.b64decode(encoded)
        return (
            AESGCM(self._keyring.key(int(version)))
            .decrypt(raw[:NONCE_BYTES], raw[NONCE_BYTES:], None)
            .decode()
        )


def blind_index(key: bytes, value: str) -> str:
    return hmac.new(key, value.strip().lower().encode(), hashlib.sha256).hexdigest()
```

- Authenticated encryption, a fresh 96-bit nonce per value, stored as `<keyVersion>:<base64(nonce || ciphertext+tag)>`
  so old rows stay readable after a rotation (new writes use `current`).
- Keys come from a KMS or Vault at startup, never from the image or settings defaults; build `KeyRing` once.
- Random encryption cannot be queried: store `blind_index(hmac_key, value)` (its own key, normalised input) in an
  indexed column and search on that.

## 3. Retention (TTL)
Purge expired rows with the scheduled job of `python-messaging` §7 and `python-cd` §7: one batched
`purge_*` method per table (`SqlRetention` in `python-messaging`'s `scheduled-jobs.md`), a documented period per
data class, and the audit columns holding opaque subject ids rather than names.

## 4. Right to be forgotten: anonymise what must stay, delete what need not
### `src/my_service/repositories/erasure.py`

```python
from dataclasses import dataclass
from uuid import uuid4

from sqlalchemy import delete, update
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from my_service.repositories.orm import OrderRow, OutboxRow


@dataclass(frozen=True)
class ErasureResult:
    orders_anonymized: int
    outbox_rows_deleted: int


class SqlErasure:
    def __init__(self, factory: async_sessionmaker[AsyncSession]) -> None:
        self._factory = factory

    async def erase_customer(self, customer_id: str) -> ErasureResult:
        tombstone = f"erased-{uuid4()}"
        async with self._factory() as session, session.begin():
            orders = await session.execute(
                update(OrderRow)
                .where(OrderRow.customer_id == customer_id)
                .values(customer_id=tombstone, version=OrderRow.version + 1)
                .returning(OrderRow.id)
            )
            outbox = await session.execute(
                delete(OutboxRow)
                .where(OutboxRow.payload["customer_id"].astext == customer_id)
                .returning(OutboxRow.id)
            )
            return ErasureResult(len(orders.all()), len(outbox.all()))
```

In one transaction the customer's orders (kept for accounting) get a random tombstone id and a bumped version, and
the customer's outbox events are deleted. Also cover the places PII survives a plain delete: soft-deleted rows,
broker topics (keep events ids-only, or encrypt per subject and delete the key), caches (`python-persistence` §7:
invalidate the subject's keys), backups (they age out under retention).

## Tests
### `tests/integration/test_privacy.py`

```python
import os
from uuid import uuid4

from sqlalchemy import Column, MetaData, String, Table, Uuid, insert, select, text
from sqlalchemy.ext.asyncio import AsyncEngine, async_sessionmaker

from my_service.repositories.encrypted_type import EncryptedString, KeyRing, blind_index
from my_service.repositories.erasure import SqlErasure
from my_service.repositories.order_repository import SqlOrderRepository
from my_service.repositories.orm import OrderRow, OutboxRow

KEY_V1 = os.urandom(32)
KEY_V2 = os.urandom(32)
BLIND_KEY = os.urandom(32)


async def test_eraseCustomer_anonymizesOrdersAndDeletesEventsOfThatCustomerOnly(
    engine: AsyncEngine, clean_tables: None
) -> None:
    factory = async_sessionmaker(engine, expire_on_commit=False)
    mine, other = uuid4(), uuid4()
    async with factory() as s, s.begin():
        s.add(OrderRow(id=mine, customer_id="jane@example.com", total_cents=5, status="paid"))
        s.add(OrderRow(id=other, customer_id="bob@example.com", total_cents=7, status="new"))
        for customer in ("jane@example.com", "bob@example.com"):
            s.add(
                OutboxRow(
                    id=uuid4(),
                    topic="t",
                    key="k",
                    event_type="E",
                    payload={"customer_id": customer},
                )
            )
    result = await SqlErasure(factory).erase_customer("jane@example.com")
    assert (result.orders_anonymized, result.outbox_rows_deleted) == (1, 1)
    async with factory() as s:
        repo = SqlOrderRepository(s)
        assert await repo.list_by_customer("jane@example.com", 10) == []
        kept = await repo.get(mine)
        assert kept.customer_id.startswith("erased-")
        assert kept.total_cents == 5
        assert kept.version == 2
        assert (await repo.get(other)).customer_id == "bob@example.com"
        remaining = (await s.scalars(select(OutboxRow.payload))).all()
    assert remaining == [{"customer_id": "bob@example.com"}]


def _people(keyring: KeyRing) -> Table:
    return Table(
        "person_enc_test",
        MetaData(),
        Column("id", Uuid, primary_key=True),
        Column("email", EncryptedString(keyring), nullable=False),
        Column("email_index", String(64), index=True, nullable=False),
    )


async def test_encryptedString_storesCiphertext_rotatesKeys_andIsSearchableByBlindIndex(
    engine: AsyncEngine,
) -> None:
    people_v1 = _people(KeyRing(((1, KEY_V1),), current=1))
    people_v2 = _people(KeyRing(((1, KEY_V1), (2, KEY_V2)), current=2))
    old_id, new_id = uuid4(), uuid4()
    async with engine.begin() as conn:
        await conn.run_sync(people_v1.create)
        await conn.execute(
            insert(people_v1).values(
                id=old_id,
                email="jane@example.com",
                email_index=blind_index(BLIND_KEY, "Jane@Example.com"),
            )
        )
        await conn.execute(
            insert(people_v2).values(
                id=new_id,
                email="bob@example.com",
                email_index=blind_index(BLIND_KEY, "bob@example.com"),
            )
        )
    async with engine.connect() as conn:
        raw = {
            row.id: row.email
            for row in await conn.execute(text("SELECT id, email FROM person_enc_test"))
        }
        found = await conn.execute(
            select(people_v2.c.email).where(
                people_v2.c.email_index == blind_index(BLIND_KEY, "jane@example.com")
            )
        )
        bob = await conn.scalar(select(people_v2.c.email).where(people_v2.c.id == new_id))
    assert "example.com" not in raw[old_id] + raw[new_id]
    assert raw[old_id].startswith("1:")
    assert raw[new_id].startswith("2:")
    assert found.scalar_one() == "jane@example.com"
    assert bob == "bob@example.com"
    async with engine.begin() as conn:
        await conn.run_sync(people_v2.drop)
```


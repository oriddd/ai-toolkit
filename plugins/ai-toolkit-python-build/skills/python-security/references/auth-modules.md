# python-security — principal, token verifier and the FastAPI dependencies

Back to [`SKILL.md`](../SKILL.md) §1 and §2. The verifier takes a `SigningKeySource`, so the tests sign tokens with a
key generated in the test and serve the JWKS from a stdlib `HTTPServer` on a free port.

## Principal and verifier

### `src/my_service/models/principal.py`

```python
from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class Principal:
    subject: str
    scopes: frozenset[str]

    def has_scope(self, scope: str) -> bool:
        return scope in self.scopes
```

### `src/my_service/security/token_verifier.py`

```python
from typing import Protocol

import jwt

from my_service.errors.base import DependencyUnavailableError, NotAuthenticatedError
from my_service.models.principal import Principal

ALLOWED_ALGORITHMS = ["RS256", "ES256"]  # never derived from the token header


class SigningKeySource(Protocol):  # security/token_verifier.py
    def key_for(self, token: str) -> jwt.PyJWK: ...


class JwksKeySource:  # production adapter; tests pass a fake key source
    def __init__(self, jwks_url: str) -> None:
        self._client = jwt.PyJWKClient(jwks_url, cache_keys=True, timeout=5)

    def key_for(self, token: str) -> jwt.PyJWK:  # blocking HTTP on a cache miss
        return self._client.get_signing_key_from_jwt(token)


class TokenVerifier(Protocol):
    def verify(self, token: str) -> Principal: ...


class JwtTokenVerifier:
    def __init__(self, keys: SigningKeySource, issuer: str, audience: str) -> None:
        self._keys, self._issuer, self._audience = keys, issuer, audience

    def verify(self, token: str) -> Principal:
        try:
            key = self._keys.key_for(token)
            claims = jwt.decode(
                token,
                key=key,
                algorithms=ALLOWED_ALGORITHMS,
                audience=self._audience,
                issuer=self._issuer,
                options={"require": ["exp", "iat", "sub", "iss", "aud"]},
                leeway=30,
            )
        except jwt.PyJWKClientConnectionError as exc:  # IdP unreachable: 503, not 401
            raise DependencyUnavailableError(dependency="identity-provider") from exc
        except jwt.PyJWTError as exc:
            raise NotAuthenticatedError() from exc
        scopes = frozenset(str(claims.get("scope", "")).split())
        return Principal(subject=str(claims["sub"]), scopes=scopes)
```

## Dependencies

### `src/my_service/api/security.py`

```python
from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from my_service.api.dependencies import get_token_verifier
from my_service.errors.base import AccessDeniedError, NotAuthenticatedError
from my_service.models.principal import Principal
from my_service.security.token_verifier import TokenVerifier

bearer = HTTPBearer(auto_error=False)  # api/security.py


# sync def on purpose: PyJWKClient does blocking I/O, FastAPI runs it in the threadpool
def get_principal(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    verifier: Annotated[TokenVerifier, Depends(get_token_verifier)],
) -> Principal:
    if credentials is None:
        raise NotAuthenticatedError()
    return verifier.verify(credentials.credentials)


class RequireScope:
    def __init__(self, scope: str) -> None:
        self._scope = scope

    def __call__(self, principal: Annotated[Principal, Depends(get_principal)]) -> Principal:
        if not principal.has_scope(self._scope):
            raise AccessDeniedError()
        return principal


OrdersReader = Annotated[Principal, Depends(RequireScope("orders:read"))]
OrdersWriter = Annotated[Principal, Depends(RequireScope("orders:write"))]
```

## Tests

### `tests/unit/test_token_verifier.py`

```python
import json
import threading
import time
from collections.abc import Iterator
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from jwt.algorithms import RSAAlgorithm

from my_service.errors.base import DependencyUnavailableError, NotAuthenticatedError
from my_service.security.token_verifier import JwksKeySource, JwtTokenVerifier

ISSUER = "https://idp.test"
AUDIENCE = "my-service"
PRIVATE_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
PUBLIC_JWK: dict[str, Any] = RSAAlgorithm.to_jwk(PRIVATE_KEY.public_key(), as_dict=True) | {
    "alg": "RS256",
    "kid": "k1",
}


class FakeKeySource:
    def key_for(self, token: str) -> jwt.PyJWK:
        return jwt.PyJWK.from_dict(PUBLIC_JWK)


class UnreachableKeySource:
    def key_for(self, token: str) -> jwt.PyJWK:
        raise jwt.PyJWKClientConnectionError("idp down")


def _token(**overrides: object) -> str:
    now = int(time.time())
    claims: dict[str, object] = {
        "sub": "u1",
        "iss": ISSUER,
        "aud": AUDIENCE,
        "iat": now,
        "exp": now + 300,
        "scope": "orders:read orders:write",
    }
    claims.update(overrides)
    return jwt.encode(claims, PRIVATE_KEY, algorithm="RS256", headers={"kid": "k1"})


@pytest.fixture
def verifier() -> JwtTokenVerifier:
    return JwtTokenVerifier(FakeKeySource(), ISSUER, AUDIENCE)


def test_verify_validToken_returnsPrincipalWithScopes(verifier: JwtTokenVerifier) -> None:
    principal = verifier.verify(_token())
    assert principal.subject == "u1"
    assert principal.scopes == {"orders:read", "orders:write"}


@pytest.mark.parametrize(
    "token",
    [
        _token(exp=int(time.time()) - 3600),
        _token(aud="someone-else"),
        _token(iss="https://evil.test"),
        jwt.encode({"sub": "u1"}, "secret" * 8, algorithm="HS256"),
        "not-a-token",
    ],
    ids=["expired", "wrong_audience", "wrong_issuer", "hs256", "garbage"],
)
def test_verify_invalidToken_raisesNotAuthenticated(verifier: JwtTokenVerifier, token: str) -> None:
    with pytest.raises(NotAuthenticatedError):
        verifier.verify(token)


def test_verify_identityProviderDown_raisesDependencyUnavailable() -> None:
    verifier = JwtTokenVerifier(UnreachableKeySource(), ISSUER, AUDIENCE)
    with pytest.raises(DependencyUnavailableError):
        verifier.verify(_token())


class _JwksHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        body = json.dumps({"keys": [PUBLIC_JWK]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        return None


@pytest.fixture
def jwks_url() -> Iterator[str]:
    server = HTTPServer(("127.0.0.1", 0), _JwksHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield f"http://127.0.0.1:{server.server_port}/jwks.json"
    server.shutdown()
    server.server_close()


def test_jwksKeySource_servedKey_verifiesTokenSignedWithIt(jwks_url: str) -> None:
    verifier = JwtTokenVerifier(JwksKeySource(jwks_url), ISSUER, AUDIENCE)
    assert verifier.verify(_token()).subject == "u1"


def test_jwksKeySource_closedPort_raisesDependencyUnavailable() -> None:
    verifier = JwtTokenVerifier(JwksKeySource("http://127.0.0.1:1/jwks.json"), ISSUER, AUDIENCE)
    with pytest.raises(DependencyUnavailableError):
        verifier.verify(_token())
```

### `tests/unit/test_privacy.py`

```python
import logging
import os

import pytest
import structlog
from sqlalchemy.ext.asyncio import create_async_engine

from my_service.observability.logging import configure_logging
from my_service.observability.pii_masking import mask_pii, mask_value
from my_service.repositories.encrypted_type import EncryptedString, KeyRing, blind_index

KEY_V1 = os.urandom(32)
KEY_V2 = os.urandom(32)
DIALECT = create_async_engine("postgresql+asyncpg://u@h/d").dialect


def test_maskValue_keepsOnlyTheFirstCharacter() -> None:
    assert mask_value("jane") == "j***"
    assert mask_value("") == ""


def test_maskPii_nestedStructuresAndEmbeddedEmails_areMasked() -> None:
    masked = mask_pii(
        None,
        "info",
        {
            "event": "contact jane@example.com now",
            "email": "jane@example.com",
            "customer": {"phone": "555-1234", "items": [{"name": "Jane"}, 3, None]},
            "count": 3,
            "ip": None,
        },
    )
    assert masked["event"] == "contact j*** now"
    assert masked["email"] == "j***"
    assert masked["customer"] == {"phone": "5***", "items": [{"name": "J***"}, 3, None]}
    assert masked["count"] == 3
    assert masked["ip"] is None


def test_logging_structlogAndStdlibAccessLog_neverEmitRawEmail(
    capsys: pytest.CaptureFixture[str],
) -> None:
    configure_logging()
    structlog.get_logger().info("customer_seen", email="jane@example.com")
    logging.getLogger("uvicorn.access").info("GET /v1/orders?customer_id=jane@example.com 200")
    captured = capsys.readouterr()
    assert "jane@example.com" not in captured.out + captured.err
    assert "customer_seen" in captured.out


def test_encryptedString_roundTrip_usesFreshNonceAndKeyVersionPrefix() -> None:
    column = EncryptedString(KeyRing(((1, KEY_V1),), current=1))
    first = column.process_bind_param("jane@example.com", DIALECT)
    second = column.process_bind_param("jane@example.com", DIALECT)
    assert first is not None
    assert first != second
    assert first.startswith("1:")
    assert "example.com" not in first
    assert column.process_result_value(first, DIALECT) == "jane@example.com"


def test_encryptedString_rotatedKeyring_stillReadsOldRows() -> None:
    old = EncryptedString(KeyRing(((1, KEY_V1),), current=1))
    rotated = EncryptedString(KeyRing(((1, KEY_V1), (2, KEY_V2)), current=2))
    sealed_old = old.process_bind_param("a@b.co", DIALECT)
    sealed_new = rotated.process_bind_param("a@b.co", DIALECT)
    assert sealed_new is not None
    assert sealed_new.startswith("2:")
    assert rotated.process_result_value(sealed_old, DIALECT) == "a@b.co"


def test_encryptedString_none_staysNone() -> None:
    column = EncryptedString(KeyRing(((1, KEY_V1),), current=1))
    assert column.process_bind_param(None, DIALECT) is None
    assert column.process_result_value(None, DIALECT) is None


def test_blindIndex_isNormalisedAndKeyed() -> None:
    assert blind_index(KEY_V1, " Jane@Example.com ") == blind_index(KEY_V1, "jane@example.com")
    assert blind_index(KEY_V1, "a") != blind_index(KEY_V2, "a")
```

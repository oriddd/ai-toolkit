---
name: python-security
description: >
  Python / FastAPI security — JWT bearer authentication as a dependency, scope and object-level authorization,
  OWASP API Top 10 basics, secrets, CORS, docs exposure, dependency audit. Use when an endpoint needs authn/authz,
  a service handles untrusted input or secrets, or before exposing a service.
tier: should
applies_to: [rest]
depends_on: [python-code-structure, python-fastapi-conventions, python-error-handling]
ships_templates: false
hitl: true
version: 1.0
last_reviewed: 2026-11-11
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# Python Security Skill
## When to use
When an endpoint needs authentication or authorization, when the service handles secrets or untrusted input
from the internet, and before a service is exposed beyond its cluster.

## Decision gate (ask the developer before writing auth code)
1. Who calls the service: end users with tokens from an identity provider (OIDC/JWT), other services
   (client-credentials JWT or mTLS at the mesh), or nobody outside the cluster?
2. Issuer, audience and JWKS URL of the identity provider; which claim carries scopes or roles.
3. Which operations need which scope, and which resources belong to a caller (object-level rules).

Do not invent an issuer, a scope model or a "temporary" shared secret. If the service is internal and needs no
authorization, say so in the code review and skip §1–§2.

## Layout

```
src/my_service/
├── security/
│   └── token_verifier.py      # TokenVerifier Protocol + JwtTokenVerifier (PyJWT), no FastAPI imports
├── models/principal.py        # Principal(subject, scopes): what business code sees
└── api/security.py            # FastAPI dependencies: get_principal, RequireScope, Annotated aliases
```

## Dependencies
```toml
dependencies = ["pyjwt[crypto]>=2.10"]

[dependency-groups]
dev = ["pip-audit>=2.7"]
```

## 1. Authentication: verify the token in one dependency
```python
ALLOWED_ALGORITHMS = ["RS256", "ES256"]           # never derived from the token header

class JwtTokenVerifier:                           # security/token_verifier.py
    def __init__(self, keys: SigningKeySource, issuer: str, audience: str) -> None:
        self._keys, self._issuer, self._audience = keys, issuer, audience

    def verify(self, token: str) -> Principal:
        try:
            key = self._keys.key_for(token)       # PyJWKClient(jwks_url, cache_keys=True, timeout=5)
            claims = jwt.decode(
                token, key=key, algorithms=ALLOWED_ALGORITHMS,
                audience=self._audience, issuer=self._issuer,
                options={"require": ["exp", "iat", "sub", "iss", "aud"]}, leeway=30,
            )
        except jwt.PyJWKClientConnectionError as exc:      # IdP unreachable: 503, not 401
            raise DependencyUnavailableError(dependency="identity-provider") from exc
        except jwt.PyJWTError as exc:
            raise NotAuthenticatedError() from exc
        return Principal(subject=str(claims["sub"]), scopes=frozenset(str(claims.get("scope", "")).split()))
```

```python
bearer = HTTPBearer(auto_error=False)             # api/security.py

def get_principal(                                # sync def on purpose: PyJWKClient does blocking I/O,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],   # FastAPI runs it in
    verifier: Annotated[TokenVerifier, Depends(get_token_verifier)],                 # the threadpool
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

- The verifier is built once in the lifespan and read from `app.state`; tests override `get_token_verifier`
  with a fake that maps fixed tokens to principals, and unit-test `JwtTokenVerifier` with a key generated in
  the test (expired, wrong audience, wrong issuer, HS256 token, garbage, IdP down).
- `auto_error=False` so a missing token goes through our handler: `NotAuthenticatedError` is a
  `DomainError` with status 401 and `headers = {"WWW-Authenticate": "Bearer"}` (`python-error-handling` §1).
- Never `options={"verify_signature": False}`, never `algorithms=None`, never accept `alg: none` or HS256 with a
  public key as secret. Never log the token.
- Route functions receive `Principal` (`caller: OrdersWriter`) and pass it to the use case; business code never
  reads headers.

## 2. Authorization: scope at the edge, ownership in the use case
- **Function level:** every route declares its scope with an `Annotated` alias; a route without one is a review
  BLOCKER unless it is deliberately public (`/health/*`).
- **Object level (OWASP API1, BOLA):** the use case checks that the caller may touch *this* resource, after
  loading it and before acting:

```python
async def get(self, order_id: UUID, caller: Principal) -> Order:
    async with self._uow_factory() as uow:
        order = await uow.orders.get(order_id)
    if not (caller.subject == order.customer_id or caller.has_scope(ADMIN_SCOPE)):
        raise OrderNotFoundError(order_id=order_id)   # 404, not 403: do not confirm the id exists
    return order
```

- Collection endpoints filter by the caller (or reject a foreign `customer_id` with 403); never return
  everything and filter in the client.
- Never take the caller identity from the body or a query parameter; it comes from the verified token.

## 3. OWASP basics for a FastAPI service
| Risk | Rule |
| --- | --- |
| Injection | SQLAlchemy statements with bound parameters only (`python-persistence` §6); no `text()` with f-strings; `subprocess` with an argument list, never `shell=True`. |
| Mass assignment | Request models use `extra="forbid"` and never contain server-owned fields (`id`, `version`, `owner`) (`python-input-validation`). |
| Excessive data exposure | Explicit `response_model`; never return ORM rows or dicts (`python-fastapi-conventions` §3). |
| Unrestricted resource use | Bounded page sizes; request body size and rate limits at the ingress or gateway (uvicorn has no body limit). |
| SSRF | Outbound base URLs come from settings, never from requests; path segments are quoted (`python-external-client` §3). |
| Unsafe deserialisation | No `pickle`, `yaml.load` or `eval` on external data; `yaml.safe_load` only. |
| Security misconfiguration | Error bodies never carry stack traces (`python-error-handling` §4); docs off in production (§4). |
| Vulnerable components | `pip-audit` in CI (§6). |

Ruff's `S` (bandit) rules are on in `python-static-analysis`; a `# noqa: S...` needs a reason.

## 4. CORS, docs and headers
```python
app = FastAPI(
    lifespan=lifespan,
    docs_url="/docs" if settings.expose_docs else None,     # off by default
    redoc_url=None,
    openapi_url="/openapi.json" if settings.expose_docs else None,
)
if settings.cors_origins:                                   # only for browser clients
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,                # explicit list from settings, never "*" with credentials
        allow_methods=["GET", "POST"],
        allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
        expose_headers=["Location", "X-Request-ID"],
        allow_credentials=False,                            # bearer tokens need no cookies
    )
```

- `cors_origins: list[str] = []` in `AppSettings`; pydantic-settings reads a list from JSON
  (`CORS_ORIGINS='["https://shop.example.com"]'`). A service called only by other services adds no CORS at all.
- Run uvicorn behind the ingress with `--proxy-headers --forwarded-allow-ips=<ingress CIDR>` so client IPs and
  the scheme are right; never `--forwarded-allow-ips='*'` on a pod reachable directly.
- Security headers (`Strict-Transport-Security`, `X-Content-Type-Options: nosniff`) are set once, at the ingress.
- Keep `/metrics` and `/docs` off the public ingress (`python-observability` §4).

## 5. Secrets
- Secrets are `SecretStr` fields in pydantic-settings, read from the environment or mounted files
  (`SettingsConfigDict(secrets_dir="/run/secrets")`), never defaults in code, `.env` committed, or image build args.
- `SecretStr` keeps them out of `repr` and logs; call `get_secret_value()` only where the secret is used
  (the HTTP client factory, the database URL).
- Rotate without redeploying code: the settings read the value at startup; a restart picks up the new secret.
- If the service stores user passwords (rare for a microservice), hash with Argon2id (`argon2-cffi`), never a
  fast hash.

## 6. Dependency audit
Run `uv run pip-audit` in a scheduled CI job and on every lock-file change (`python-ci` §4); fix by upgrading,
or ignore one advisory with `--ignore-vuln <ID>` plus a ticket. Renovate/Dependabot keeps `uv.lock` current.

## Do / Don't
- ✅ One `get_principal` dependency; a scope alias on every non-public route.
- ✅ Object-level checks in the use case; 404 for resources the caller may not see.
- ✅ Algorithm allow-list, required `exp`/`aud`/`iss`, JWKS fetched off the event loop.
- ✅ Explicit CORS origins from settings; docs disabled unless `expose_docs`.
- ❌ `jwt.decode(..., options={"verify_signature": False})`, or trusting the token's `alg` header.
- ❌ Caller identity from the body, query or a custom header.
- ❌ `allow_origins=["*"]` with `allow_credentials=True`; CORS on a service-to-service API.
- ❌ Secrets in code, logs, error messages, `.env` in git or Docker build args.
- ❌ `HTTPException(401)` from services; raise `NotAuthenticatedError` / `AccessDeniedError`.

## Cross-references
- `python-error-handling` — 401/403 catalogue entries and the `WWW-Authenticate` header.
- `python-fastapi-conventions` — dependencies and the app factory.
- [`python-input-validation`](../python-input-validation/SKILL.md) — `extra="forbid"`, bounded inputs.
- [`python-external-client`](../python-external-client/SKILL.md) — SSRF-safe outbound calls.
- `python-static-analysis` — ruff `S` rules; `python-ci` — `pip-audit`.

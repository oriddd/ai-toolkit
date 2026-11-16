---
name: permissions
description: >
  Java / Spring Boot authorization via Strategy + Handler — PermissionsHandler dispatches by caller context (user,
  service account, external system) to PermissionsCheckStrategy beans. Use when deciding who may call an endpoint
  (admins, resource owner, service-account scopes).
tier: must
applies_to: [rest, monolith]
depends_on: [code-structure, exception-handling, strategy-registry-pattern]
ships_templates: true
hitl: false
version: 1.3
last_reviewed: 2026-11-15
---

# Permissions Skill
> **Pattern Foundation:** This skill is a concrete application of the strategy-registry-pattern skill. 
> Read that skill first to understand the foundational pattern, then return here for the permissions-specific implementation.

This skill provisions the **authorization layer** of a Spring Boot
microservice using a pluggable Strategy + Handler + Registry:

```
permission/
├── CallerContext.java                       # enum: USER / SERVICE_ACCOUNT / EXTERNAL_SYSTEM / BASIC_AUTH …
├── CallerContextResolver.java               # Resolver: read the current principal and return a CallerContext
├── PermissionsCheckStrategy.java            # Strategy interface: defines the contract
├── PermissionsHandler.java                  # Handler: orchestrates resolver → registry → strategy
├── PermissionsRegistry.java                 # Registry: routes CallerContext → strategy (List injection)
└── strategy/
    ├── ScopeBasedPermissionsCheck.java      # Strategy: SERVICE_ACCOUNT_CONTEXT → OAuth2 scope allow-list
    ├── ResourcePermissionsCheck.java        # Strategy: USER_CONTEXT → query an authorization source per resource
    └── NoOpPermissionsCheck.java            # Strategy: BASIC_AUTH (trusted callers: allow-list only, no resource check)
```

> **Pattern Application:** This follows the **Handler-based variation** of the strategy-registry-pattern.
> Components: Handler → Resolver (CallerContext) → Registry → Strategy (permissions check)

The skill **does not bind to a specific JWT library, claim shape, or
authorization back-end** — those are plug-points:

| Plug-point | Default | Where your own binding plugs in |
| --- | --- | --- |
| Reading the authenticated principal | `SecurityContextHolder.getContext().getAuthentication()` (Spring Security) | Provide a `CallerContextResolver` implementation that reads your authentication token shape and maps it to `CallerContext`. |
| Source of "is this user allowed for this resource?" | abstract `ResourceAuthorizationSource` interface – the skill stubs it | Provide a `ResourceAuthorizationSource` implementation backed by your authorization service. |

## When to invoke

- A new microservice that exposes user-facing data is being created.
- A new caller type must be supported (add a new strategy + extend the enum).
- A new endpoint must enforce per-resource permissions (call
  `permissionsHandler.handle(resourceIds...)` inside the operation).

## Inputs (ask the developer)

| # | Question | Default |
| - | -------- | ------- |
| 1 | Base package for the new code (e.g. `com.example.foo`)? | derive from `pom.groupId` + `artifactId` |
| 2 | Which caller-context values must the service accept? (multi-select: `USER`, `SERVICE_ACCOUNT`, `EXTERNAL_SYSTEM`, `BASIC_AUTH`, …) | `USER` + `SERVICE_ACCOUNT` |
| 3 | What identifies a "resource" the caller must own? (one or two ids – e.g. `resourceId` + `itemId`, `accountId`, `tenantId`) | `resourceId` |
| 4 | For `SERVICE_ACCOUNT`: which OAuth2 scopes are allowed (comma list)? | `read` |
| 5 | For `USER` / `EXTERNAL_SYSTEM`: should authorization be evaluated locally (claims on the token) or remotely (via a query service)? | `remotely` |
| 6 | If remote: name + base URL + endpoint of the authorization source. | — (wired via the `external-client` skill) |

## Files to generate

### 1. Dependencies
- `org.springframework.boot:spring-boot-starter-oauth2-resource-server` — required: the `SecurityConfig` template
  validates JWTs (`oauth2ResourceServer().jwt()`), and with `spring-boot-starter-security` alone the context fails
  at startup (`NoClassDefFoundError: BearerTokenResolver`). Plain `spring-boot-starter-security` only for a
  service without OAuth2 tokens (e.g. HTTP Basic only).

### 2. `CallerContext` (enum)

```java
public enum CallerContext { USER, SERVICE_ACCOUNT, EXTERNAL_SYSTEM, BASIC_AUTH }
```

The set of values is **project-specific** — only include the ones the
service actually accepts (Phase 1 #2).

### 3. `CallerContextResolver` (SPI)

```java
public interface CallerContextResolver {
    /** Returns the context of the current request's principal, or {@code null} if absent. */
    @Nullable CallerContext resolve();   // org.jspecify.annotations.Nullable — NullAway forces the handler's null check
    /** Returns the current principal's OAuth2 scopes, {@code SCOPE_} prefix stripped (empty if none). */
    Set<String> grantedScopes();
}
```

A default `SpringSecurityCallerContextResolver` reads
`SecurityContextHolder.getContext().getAuthentication()` and inspects the
authorities to bucket the call into one of the enum values, and exposes the granted scopes. You can override this bean to read
your own claim instead.

Default bucketing (adjust to your identity provider and record it in an ADR):

| Authentication | `CallerContext` |
| --- | --- |
| `JwtAuthenticationToken` from a client-credentials grant (no end user: `sub` equals the `client_id` / `azp` claim) | `SERVICE_ACCOUNT` |
| `JwtAuthenticationToken` with an end-user `sub` | `USER` |
| `JwtAuthenticationToken` whose issuer is a configured external-partner issuer | `EXTERNAL_SYSTEM` |
| `UsernamePasswordAuthenticationToken` (HTTP Basic — only if `SecurityConfig` enables `httpBasic`) | `BASIC_AUTH` |
| anonymous / no authentication | `null` (the handler answers 403) |

### 4. `PermissionsCheckStrategy` (interface)

```java
public interface PermissionsCheckStrategy {
    void verifyPermissions(final String resourceId);   // throws the unchecked ForbiddenException
    List<CallerContext> supportedContexts();
}
```

Adjust the `verifyPermissions` signature to the resource-id shape (Phase 1 #3).

### 5. `PermissionsHandler` (Handler/Dispatcher)

```java
@Component
@Slf4j
@RequiredArgsConstructor
public class PermissionsHandler {
    private final CallerContextResolver callerContextResolver;
    private final PermissionsRegistry permissionsRegistry;

    public void handle(final String resourceId) {
        final CallerContext ctx = callerContextResolver.resolve();
        if (ctx == null) {
            throw ExceptionMessages.callerContextNotFound();          // ForbiddenException → 403
        }
        permissionsRegistry.getStrategy(ctx)
                .orElseThrow(() -> ExceptionMessages.unrecognizedCallerContext(ctx))   // ForbiddenException → 403
                .verifyPermissions(resourceId);
    }
}
```

### 5a. `PermissionsRegistry` (Registry/Router)

```java
@Component
public class PermissionsRegistry {
    private final Map<CallerContext, PermissionsCheckStrategy> strategiesByContext;

    // Spring injects ALL PermissionsCheckStrategy beans automatically
    public PermissionsRegistry(final List<PermissionsCheckStrategy> strategies) {
        final Map<CallerContext, PermissionsCheckStrategy> byContext = new EnumMap<>(CallerContext.class);
        for (final PermissionsCheckStrategy strategy : strategies) {
            for (final CallerContext context : strategy.supportedContexts()) {
                if (byContext.putIfAbsent(context, strategy) != null) {
                    throw new IllegalStateException("Two permission strategies support " + context);
                }
            }
        }
        this.strategiesByContext = Map.copyOf(byContext);
    }

    public Optional<PermissionsCheckStrategy> getStrategy(final CallerContext callerContext) {
        return Optional.ofNullable(callerContext).map(strategiesByContext::get);
    }
}
```

The map is built once and a duplicate discriminator fails startup, so
routing never depends on bean order.

### 6. Concrete strategies (generate only the ones the developer selected)

`ScopeBasedPermissionsCheck` (`SERVICE_ACCOUNT`, scope allow-list from configuration), `ResourcePermissionsCheck`
(`USER` / `EXTERNAL_SYSTEM`, per-resource check through the fail-closed `ResourceAuthorizationSource` SPI) and
`NoOpPermissionsCheck` (`BASIC_AUTH`, allow-list only, needs an ADR). Each is a `@Component` collected by list
injection — **never** add `if/else` on `CallerContext` in the handler. Rules and wiring:
[`references/concrete-strategies.md`](./references/concrete-strategies.md).

### 7. `application.yaml`

Merge these under the existing top-level keys of `application.yaml` (the `code-structure` template already has `spring:`;
a second `spring:` block is a duplicate key and the app fails to start), or write the `spring.security…` keys dotted:

```yaml
permissions:
  service-account:
    allowed-scopes: ${PERMISSIONS_ALLOWED_SCOPES:{{defaultScopes}}}

spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: ${JWT_ISSUER_URI}
          audiences: ${JWT_AUDIENCE:{{artifactId}}}   # reject tokens minted for other services
```

`JWT_ISSUER_URI` is required: without it the service does not start on the default profile, so list it (and
`JWT_AUDIENCE`) wherever the service is configured — Helm `jwt.issuerUri` / `jwt.audience` (`cd`), the README, and
`application-local.yaml` (the issuer URL is not a secret, so a local default is allowed, `spring-boot-conventions` §2):

```yaml
spring.security.oauth2.resourceserver.jwt.issuer-uri: http://localhost:8081/realms/dev
```

Tests set their own value (`component-tests` §3, `integration-tests`).

Bind `permissions.*` with a `PermissionsProperties` `@ConfigurationProperties`
record (`spring-boot-conventions` §1). Also add a `ConfigurationConstants`
entry per property: the `permissions` prefix constant in
`constant/ConfigurationConstants`, used in `@ConfigurationProperties(prefix = …)`.

### 8. Exception type

Ensure `exception/ForbiddenException.java` (unchecked, from the
`exception-handling` templates) exists and that
`exception/constants/ExceptionMessages` has these message templates, each
with a factory method returning `ForbiddenException`:

- `CALLER_CONTEXT_NOT_FOUND` → `callerContextNotFound()` (shipped)
- `UNRECOGNIZED_CALLER_CONTEXT` ("Unrecognized caller context: {0}") → `unrecognizedCallerContext(ctx)` (shipped)
- `CALLER_HAS_NO_PERMISSIONS` → add `callerHasNoPermissions(resourceId)`
- `SCOPES_NOT_FOUND` → add `scopesNotFound()`
- `SCOPE_NOT_ALLOWED` → add `scopeNotAllowed(scope)`

### 8a. Identity provider outage

The resource server resolves the issuer lazily, on the first token. When the issuer cannot be reached,
`JwtDecoderInitializationException` is thrown inside the filter chain, where neither the advice nor the entry point
sees it, and the container answers `500`. `IdentityProviderUnavailableFilter` (before `BearerTokenAuthenticationFilter`)
and `ProblemDetailSecurityHandler` turn it, and `AuthenticationServiceException` (JWKS fetch failure), into
`503` problem+json with `Retry-After` and `ERR_UNAVAILABLE`; a bad token stays `401`.

### 9. Controller-advice mapping
Map `ForbiddenException` → HTTP `403 FORBIDDEN` in the global
`@RestControllerAdvice` (see the `exception-handling` skill). **Never** let
the strategy translate to HTTP types itself.

### 10. Wire into operations
Inside every `Operation` that exposes a resource:

```java
permissionsHandler.handle(resourceId);
// …then proceed with the use case
```

This must be the **first** call after parameter validation. Validation
of the id being authorized must stay **syntactic** (format, length, required):
a validator that loads that resource (existence, a product's type) runs before
authorization, and answering 400 for missing / ineligible ids while eligible
ones reach the 403 tells any caller which ids exist — even with one generic
message. Run such checks in the operation, after this call. Lookups of other
*referenced* ids in the request stay in the validation layer.

## Tests (use the `unit-tests` skill)

Required cases for `PermissionsHandlerTest` (happy path, no matching strategy, strategy throws, empty strategy list,
`null` context), per-strategy cases, the resolver test and the component-test wiring — plus one end-to-end security
test with the **real** `PermissionsHandler`: [`references/testing.md`](./references/testing.md).

## Validation

1. `mvn -q test` – unit tests green.
2. Hit the protected endpoint with:
   - no token → `401` (handled by Spring Security).
   - a token whose context is unknown → `403`.
   - a service-account token without the allowed scope → `403`.
   - a service-account token with the allowed scope → `2xx`.
   - a user token without permission on the resource → `403`.
   - a user token with permission on the resource → `2xx`.

## Do / Don't

✅ Add a new caller type by adding **one** new `@Component` strategy and one
new enum value – never modify the handler.
✅ Throw `ForbiddenException` (the domain exception), not Spring's
`AccessDeniedException`, from strategies. The advice translates it.
✅ Keep the `PermissionsHandler.handle(...)` call **inside the operation**,
not the controller – the operation owns the use case.
✅ Keep the `CallerContextResolver` as the only place that reads
`SecurityContextHolder` / token internals. Strategies depend on the resolver
or on injected scope lists, not on the security framework directly.
❌ Never short-circuit a context with a TODO; always provide an explicit
strategy (even a documented no-op) so the dispatcher does not throw
`UNRECOGNIZED_CALLER_CONTEXT`.
❌ Never embed authorization-back-end calls (e.g. an Index/Search service)
in this skill – isolate them behind a `ResourceAuthorizationSource` interface
and wire the real implementation via the `external-client` skill.
❌ Never embed permission logic in the controller advice – the advice only
maps the exception to a status code.

## 11. Templates

- [`PermissionsHandler.java.tmpl`](./templates/PermissionsHandler.java.tmpl) — Central permission dispatcher.
- [`PermissionsRegistry.java.tmpl`](./templates/PermissionsRegistry.java.tmpl) — Routes a `CallerContext` to its strategy.
- [`PermissionsCheckStrategy.java.tmpl`](./templates/PermissionsCheckStrategy.java.tmpl) — The strategy SPI.
- [`SecurityConfig.java.tmpl`](./templates/SecurityConfig.java.tmpl) — Spring Security baseline for the service.
- [`ProblemDetailSecurityHandler.java.tmpl`](./templates/ProblemDetailSecurityHandler.java.tmpl) — 401 / 403 from the filter chain as ProblemDetail (`security-hardening` §10).
- [`IdentityProviderUnavailableFilter.java.tmpl`](./templates/IdentityProviderUnavailableFilter.java.tmpl) — IdP unreachable → 503 problem+json (§8a).

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
version: 1.1
last_reviewed: 2026-11-11
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
- `org.springframework.boot:spring-boot-starter-security` (or
  `spring-boot-starter-oauth2-resource-server` if validating OAuth2 tokens).

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
    CallerContext resolve();
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

- **`ScopeBasedPermissionsCheck`** – for `SERVICE_ACCOUNT`. Reads an
  allow-list of OAuth2 scopes from configuration and checks the caller's
  scopes obtained from `CallerContextResolver.grantedScopes()` (the resolver
  strips the `SCOPE_` prefix that Spring Security adds) — it never reads
  `SecurityContextHolder` itself.

- **`ResourcePermissionsCheck`** – for `USER` / `EXTERNAL_SYSTEM`. Calls an
  abstract `ResourceAuthorizationSource` SPI; this skill ships an
  in-memory stub plus a `TODO` pointing the implementer at the
  `external-client` skill to add the real back-end. Your own deployment
  provides an implementation via a `@Primary @Bean`. The in-memory stub
  lives in `src/test` only; the production default is a fail-closed
  `DenyAllResourceAuthorizationSource`: `ResourcePermissionsCheck` injects an
  `ObjectProvider<ResourceAuthorizationSource>` and resolves it with
  `getIfAvailable(DenyAllResourceAuthorizationSource::new)`, so a service that
  forgot the real implementation denies every request instead of trusting a
  stub. Not `@ConditionalOnMissingBean` on a bean in your own `@Configuration`:
  there it is evaluated before other configuration classes and scanned beans
  may be registered, so it is unreliable (`spring-boot-conventions` §3).

- **`NoOpPermissionsCheck`** – for `BASIC_AUTH`. Documented no-op for
  trusted system callers. Always include this when `BASIC_AUTH` is in the
  accepted set so the dispatcher does not throw `UNRECOGNIZED_CALLER_CONTEXT`.
  It skips the **per-resource** check only: it must still verify that the
  principal is in an explicit, configured allow-list of trusted basic-auth
  users (or holds a dedicated role) and throw `ForbiddenException`
  otherwise. Any no-op strategy needs an ADR, and `BASIC_AUTH` also needs
  `httpBasic` configured in `SecurityConfig` (the shipped template is
  JWT-only).

Each is a `@Component` and is auto-collected by the handler via list
injection – **never** add `if/else` on `CallerContext` in the handler.

### 7. `application.yaml`

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
that runs before it must stay **syntactic** (format, length, required):
a validator that loads the resource (e.g. checks a product's type) runs
before authorization, so it must not reveal whether the resource exists or
echo its attributes in the 400 — move such checks after this call, or
return the same generic message for "missing" and "wrong type".

## Tests (use the `unit-tests` skill)

Required cases for `PermissionsHandlerTest`:

1. Happy path – matching strategy → no exception.
2. No matching strategy → `ForbiddenException`.
3. Strategy throws → exception propagates with original message.
4. Empty strategy list → `ForbiddenException`.
5. `CallerContext` is `null` → `ForbiddenException` with `CALLER_CONTEXT_NOT_FOUND`.

For each concrete strategy, cover:

- `supportedContexts()` returns the expected list.
- `verifyPermissions(...)` happy path.
- Every thrown-exception branch (missing authorities, scope not allowed,
  authorization source returns "no access", etc.).

Strategies never read `SecurityContextHolder` (see Do / Don't) — stub the
injected `CallerContextResolver` instead. Only the `SpringSecurityCallerContextResolver`
test reads it: set a real context with `SecurityContextHolder.setContext(...)`
(e.g. holding a `JwtAuthenticationToken`) and call
`SecurityContextHolder.clearContext()` in `@AfterEach` — no static mocking.

## Component test wiring
In `ComponentTestConfiguration`, provide a `@Primary` mock `PermissionsHandler`
whose behaviour branches on the input id so each component test can drive the
forbidden / allowed paths deterministically (see the `component-tests` skill).

That mock bypasses the resolver, registry and strategies, so also keep at
least one end-to-end security test (e.g. `FooSecurityTest`) that uses the
**real** `PermissionsHandler`, fakes only the `ResourceAuthorizationSource`,
and authenticates with a real-shaped JWT (MockMvc `jwt()` post-processor from
`spring-security-test`) for an allowed and a forbidden caller.

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

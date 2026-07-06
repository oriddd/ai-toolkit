---
name: permissions
description: Wire authentication & authorization into a Spring Boot microservice using the Strategy + Handler pattern. Adds a PermissionsHandler that dispatches by a "caller context" (the type of authenticated principal — user, service-account, external system, etc.) to a pluggable PermissionsCheckStrategy, plus matching unit tests. Vendor-neutral — the caller-context type and the authorization back-end are plug-points.
tier: must
applies_to: [rest, monolith]
depends_on: [code-structure, exception-handling]
ships_templates: true
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Permissions Skill (public)

This skill provisions the **authorization layer** of a Spring Boot
microservice using a pluggable Strategy + Handler:

```
permission/
├── CallerContext.java                       # enum: USER / SERVICE_ACCOUNT / EXTERNAL_SYSTEM / BASIC_AUTH …
├── CallerContextResolver.java               # SPI: read the current principal and return a CallerContext
├── PermissionsCheckStrategy.java            # interface
├── PermissionsHandler.java                  # dispatcher (List<Strategy> + CallerContext)
└── strategies/
    ├── ScopeBasedPermissionsCheck.java      # SERVICE_ACCOUNT_CONTEXT → OAuth2 scope allow-list
    ├── ResourcePermissionsCheck.java        # USER_CONTEXT → query an authorization source per resource
    └── NoOpPermissionsCheck.java            # BASIC_AUTH (trusted callers, documented no-op)
```

The skill **does not bind to a specific JWT library, claim shape, or
authorization back-end** — those are plug-points:

| Plug-point | Public default | Where an internal binding plugs in |
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
| 3 | What identifies a "resource" the caller must own? (one or two ids – e.g. `documentId` + `fileId`, `caseId`, `tenantId`) | `resourceId` |
| 4 | For `SERVICE_ACCOUNT`: which OAuth2 scopes are allowed (comma list)? | `FileAccess` |
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
    /** @return the context of the current request's principal, or {@code null} if absent. */
    CallerContext resolve();
}
```

A default `SpringSecurityCallerContextResolver` reads
`SecurityContextHolder.getContext().getAuthentication()` and inspects the
authorities to bucket the call into one of the enum values. Internal
deployments override this bean by reading your organization's
claim instead.

### 4. `PermissionsCheckStrategy` (interface)

```java
public interface PermissionsCheckStrategy {
    void verifyPermissions(final String resourceId) throws FooForbiddenException;
    List<CallerContext> supportedContexts();
}
```

Adjust the `verifyPermissions` signature to the resource-id shape (Phase 1 #3).

### 5. `PermissionsHandler` (dispatcher)

```java
@Component
@Slf4j
public class PermissionsHandler {
    private final List<PermissionsCheckStrategy> strategies;
    private final CallerContextResolver callerContextResolver;

    @Autowired
    public PermissionsHandler(final List<PermissionsCheckStrategy> strategies,
                              final CallerContextResolver callerContextResolver) {
        this.strategies = strategies;
        this.callerContextResolver = callerContextResolver;
    }

    public void handle(final String resourceId) throws FooForbiddenException {
        final CallerContext ctx = callerContextResolver.resolve();
        if (ctx == null) {
            throw new FooForbiddenException(ExceptionMessages.CALLER_CONTEXT_NOT_FOUND);
        }
        strategies.stream()
                .filter(s -> s.supportedContexts().contains(ctx))
                .findFirst()
                .orElseThrow(() -> new FooForbiddenException(
                        MessageFormat.format(ExceptionMessages.UNRECOGNIZED_CALLER_CONTEXT, ctx)))
                .verifyPermissions(resourceId);
    }
}
```

### 6. Concrete strategies (generate only the ones the developer selected)

- **`ScopeBasedPermissionsCheck`** – for `SERVICE_ACCOUNT`. Reads an
  allow-list of OAuth2 scopes from configuration and checks the
  authorities of the current `Authentication` (stripping the `SCOPE_`
  prefix that Spring Security adds).

- **`ResourcePermissionsCheck`** – for `USER` / `EXTERNAL_SYSTEM`. Calls an
  abstract `ResourceAuthorizationSource` SPI; the public skill ships an
  in-memory stub plus a `TODO` pointing the implementer at the
  `external-client` skill to add the real back-end. Internal deployments
  provide an implementation via a `@Primary @Bean`.

- **`NoOpPermissionsCheck`** – for `BASIC_AUTH`. Documented no-op for
  trusted system callers. Always include this when `BASIC_AUTH` is in the
  accepted set so the dispatcher does not throw `UNRECOGNIZED_CALLER_CONTEXT`.

Each is a `@Component` and is auto-collected by the handler via list
injection – **never** add `if/else` on `CallerContext` in the handler.

### 7. `application.yaml`

```yaml
permissions:
  service-account:
    allowed-scopes: ${PERMISSIONS_ALLOWED_SCOPES:{{defaultScopes}}}
```

Also add a `ConfigurationConstants` entry per property.

### 8. Exception type

Ensure `exception/<Domain>ForbiddenException.java` exists and add static
messages to `exception/constants/ExceptionMessages`:

- `CALLER_CONTEXT_NOT_FOUND`
- `UNRECOGNIZED_CALLER_CONTEXT` ("Unrecognized caller context: {0}")
- `CALLER_HAS_NO_PERMISSIONS`
- `SCOPES_NOT_FOUND`
- `SCOPE_NOT_ALLOWED`

### 9. Controller-advice mapping
Map `<Domain>ForbiddenException` → HTTP `403 FORBIDDEN` in the global
`@RestControllerAdvice` (see the `exception-handling` skill). **Never** let
the strategy translate to HTTP types itself.

### 10. Wire into operations
Inside every `Operation` that exposes a resource:

```java
permissionsHandler.handle(resourceId);
// …then proceed with the use case
```

This must be the **first** call after parameter validation.

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

If a strategy reads from `SecurityContextHolder`, use
`MockedStatic<SecurityContextHolder>` inside a `try-with-resources` block.

## Component test wiring
In `ComponentTestConfiguration`, provide a `@Primary` mock `PermissionsHandler`
whose behaviour branches on the input id so each component test can drive the
forbidden / allowed paths deterministically (see the `component-tests` skill).

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
✅ Throw `*ForbiddenException` (the domain exception), not Spring's
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

## 4. Templates

- [`PermissionsHandler.java.tmpl`](./templates/PermissionsHandler.java.tmpl) — Central permission dispatcher.
- [`SecurityConfig.java.tmpl`](./templates/SecurityConfig.java.tmpl) — Spring Security baseline for the service.

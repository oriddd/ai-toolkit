# Permissions Skill — tests

Part of the [`permissions`](../SKILL.md) skill.

## Tests (use the `unit-tests` skill)

The handler, registry, scope strategy, resolver and both security-handler classes ship with their tests (SKILL.md §11); the lists below
are what those tests cover and what a new strategy's test must cover. Required cases for `PermissionsHandlerTest`:

1. Happy path – matching strategy → no exception.
2. No matching strategy → `ForbiddenException`.
3. Strategy throws → exception propagates with original message.
4. Empty strategy list → `ForbiddenException`.
5. `CallerContext` is `null` → `ForbiddenException` with `CALLER_CONTEXT_NOT_FOUND`.

For each concrete strategy, cover:

- `supportedContexts()` returns the expected list.
- `canHandle(ctx)` is `true` only for the declared contexts and `false` for `null`.
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

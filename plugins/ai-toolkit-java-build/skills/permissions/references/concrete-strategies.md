# Permissions Skill — concrete strategies

Part of the [`permissions`](../SKILL.md) skill.

## 6. Concrete strategies (generate only the ones the developer selected)

- **`ScopeBasedPermissionsCheck`** ([template](../templates/ScopeBasedPermissionsCheck.java.tmpl), with its test) – for `SERVICE_ACCOUNT`. Reads an
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

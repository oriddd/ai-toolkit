# Component Tests Skill — Security slice test

Part of the [`component-tests`](../SKILL.md) skill. Headings are stable; other skills cite them.

## Authenticated paths

If your service requires authentication and you want to **test the secured
controller pipeline** (not bypass it via a permissive filter chain), use
Spring Security's request post-processors instead of disabling security.
This is a **separate security test, not a component test**: it runs
**without** the `component-test` profile (so the production filter chain is
active) and drives the controller through `MockMvc`. It is a `@WebMvcTest`
slice, so no real downstream starts: the controller's collaborator is a
`@MockitoBean` (slice tests are the left-hand column of the `@MockitoBean` vs `@TestConfiguration` matrix in SKILL.md).
The slice also loads every `Filter`, `HandlerInterceptor` and `WebMvcConfigurer` bean, but not their
collaborators: with `request-metrics` that is `MetricsFilter`, `ClientIdCaptureInterceptor` and its `WebMvcConfigurer`,
so their dependencies are `@MockitoBean`s too, or the slice fails with `NoSuchBeanDefinitionException`.
The component-test rules (permissive chain, `TestRestTemplate` only) still
apply to every `*ComponentTest` class.

Test dependencies: `org.springframework.security:spring-security-test`
(test scope, for `jwt()`), plus `spring-boot-starter-oauth2-resource-server`
for a JWT resource server.

Use [`templates/SecurityTest.java.tmpl`](../templates/SecurityTest.java.tmpl) (placeholders `{{basePackage}}`,
`{{ControllerClass}}`, `{{OperationClass}}` — the controller's only collaborator — and `{{apiPath}}`, a path the
production chain requires authentication for). It proves, against the production filter chain: no token answers `401`,
a JWT with the required scope answers `200`, and an unknown path with a valid token answers `403` as
`application/problem+json` carrying `ERR-FORBIDDEN`. The parts that make the slice start:

- `@Import({SecurityConfig.class, ProblemDetailSecurityHandler.class, GlobalExceptionHandler.class})`: a `@WebMvcTest`
  loads `@RestControllerAdvice` but not plain `@Component`s, and `SecurityConfig` injects `ProblemDetailSecurityHandler`.
  Importing only `SecurityConfig` fails with `NoSuchBeanDefinitionException: ProblemDetailSecurityHandler`.
- A nested `@TestConfiguration` with a `SimpleMeterRegistry` bean: the handler counts `security.auth.failure`, and the
  slice has no `MeterRegistry` (no metrics auto-configuration).
- `properties = "spring.security.oauth2.resourceserver.jwt.issuer-uri=…"`: `application.yaml` reads `${JWT_ISSUER_URI}`
  with no default (`permissions` §7); without a value the resource-server auto-configuration cannot evaluate its
  condition and the slice does not start.
- `@MockitoBean JwtDecoder`: `jwt()` bypasses it, but the resource-server configuration still needs the bean.
- The `[request-metrics]` block (`MetricNameResolver`, `MetricsRecorderRegistry`, `ClientIdParser`): omit it without
  `request-metrics`; remove it with the `exception-handling` §3a `sed` recipe (literal tag `request-metrics`).

This proves the security configuration is wired correctly, not just the
controller logic.

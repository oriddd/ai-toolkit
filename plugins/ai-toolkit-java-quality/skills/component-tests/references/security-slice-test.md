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

```java
// issuer-uri: application.yaml reads ${JWT_ISSUER_URI} with no default (permissions §7); without a value the
// resource-server auto-configuration fails to evaluate its condition and the slice does not start
@WebMvcTest(controllers = FooController.class,
        properties = "spring.security.oauth2.resourceserver.jwt.issuer-uri=https://issuer.example.test")
@Import(SecurityConfig.class)              // the production filter chain (+ any validator / ValidationConfig the controller uses)
class FooSecurityTest {
    @Autowired MockMvc mvc;
    @MockitoBean FooOperation fooOperation; // the controller's only collaborator
    @MockitoBean JwtDecoder jwtDecoder;     // jwt() bypasses it; the resource-server config still needs the bean
    // request-metrics beans in the slice: MetricsFilter, ClientIdCaptureInterceptor (omit without request-metrics)
    @MockitoBean MetricNameResolver metricNameResolver;
    @MockitoBean MetricsRecorderRegistry metricsRecorderRegistry;
    @MockitoBean ClientIdParser clientIdParser;

    @Test
    void getFoo_noToken_returns401() throws Exception {
        mvc.perform(get("/api/v1/foo/123"))
           .andExpect(status().isUnauthorized());
    }

    @Test
    void getFoo_jwtWithRequiredScope_returns200() throws Exception {
        mvc.perform(get("/api/v1/foo/123")
                .with(jwt().jwt(b -> b.subject("alice")).authorities(new SimpleGrantedAuthority("SCOPE_read"))))
           .andExpect(status().isOk());
    }
}
```

This proves the security configuration is wired correctly, not just the
controller logic.

---
name: component-tests
description: >
  Java / Spring Boot component tests — boot the full context with a test profile, replace external collaborators with
  deterministic doubles, exercise the HTTP API end to end via TestRestTemplate. Use when adding a REST endpoint or use
  case.
tier: must
applies_to: [rest, monolith]
depends_on: [unit-tests]
ships_templates: true
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Component Tests Skill

A **component test** boots the real Spring context for the service under
`webEnvironment = RANDOM_PORT`, activates the `component-test` profile, swaps
external collaborators for in-process fakes/mocks, and drives the service
through its HTTP API. It is the contract test for the microservice and the
last line of defence before integration with the rest of the platform.

## When to invoke

- A new `@RestController` endpoint is added.
- An existing endpoint's contract changes (status codes, response shape,
  permission model).
- A new external dependency is wired in – add a fake bean in
  `ComponentTestConfiguration` and at least one happy-path + one failure test.

## Layout

```
src/test/java/<base-package>/
├── component/
│   └── <UseCase>ComponentTest.java
├── testconfig/
│   ├── ComponentTestConfiguration.java   # @TestConfiguration + @Profile("component-test")
│   └── ... (additional opt-out configs, e.g. NoHeavyStartupTestConfig)
└── testdata/
    └── TestsResourcesHolder.java         # loads classpath fixtures
src/test/resources/
├── application-component-test.yaml        # overrides for the component-test profile only
└── <fixtures>/                            # binary / text fixtures
```

## Required pieces

### 1. `ComponentTestConfiguration`

A `@TestConfiguration` annotated with `@Profile("component-test")` that:

- Disables real security (only when the service uses Spring Security —
  create-repo Q9 auth = yes; otherwise drop this bean and its imports from
  the template): provides a `SecurityFilterChain` bean that calls
  `httpSecurity.csrf(disable).authorizeHttpRequests(auth -> auth.anyRequest().permitAll())`.
  It must be the **only** `SecurityFilterChain` in the context: annotate the
  production security config with `@Profile("!component-test")`. Two
  any-request chains make Spring Security 6 fail at startup, or let the
  production chain win.
- Provides a `@Primary TestRestTemplate` with extended connect/read timeouts
  when the operation under test is slow (file conversion, ML inference, …).
- Provides `@Primary` mocks for every collaborator that touches the network
  or filesystem (e.g. `PermissionsHandler`, HTTP clients, blob-store / file-store clients).
  These mocks must be **deterministic** – branch on the input (file id, doc
  id, request body) so a single test class can exercise success, forbidden,
  not-found, and internal-error paths from one fixture set.

### 1b. Opt-out `@TestConfiguration`s for heavy startup work

Any production bean that performs expensive `@PostConstruct` work (license
loading, cache priming, schema migration, large thread pools) must have a
paired `@TestConfiguration` that replaces it with a no-op — otherwise every
component test pays the cost.

A `@Bean @Primary` mock **adds** a second bean; it does not remove the
production one. The scanned production bean is still created and its
`@PostConstruct` still runs. So also gate the production bean out of the
component-test profile (`@Profile("!component-test")` on the class, or a
`@ConditionalOnProperty` that the test profile switches off). Example
(`HeavyStartupOrchestrator` is an illustrative name):

```java
// production bean: never created under the component-test profile
@Component
@Profile("!component-test")
public class HeavyStartupOrchestrator { … @PostConstruct void load() { … } }

@TestConfiguration
@Profile("component-test")
public class NoHeavyStartupTestConfig {
    @Bean
    public HeavyStartupOrchestrator licensesLoadingOrchestrator() {
        return mock(HeavyStartupOrchestrator.class); // the only instance; nothing heavy runs
    }
}
```

Import it alongside `ComponentTestConfiguration` via `@Import({…, …})`.
(`@MockitoBean` would also replace the bean definition so the real bean is
never created, but it belongs in slice tests — see the decision matrix below.)

### 2. Test class skeleton

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import(ComponentTestConfiguration.class)
@ActiveProfiles("component-test")
class FooComponentTest {

    @LocalServerPort private int port;
    @Autowired      private TestRestTemplate restTemplate;

    private static final String URL_TEMPLATE = "http://localhost:{0}/<context-path>/api/v1/...";

    @ParameterizedTest
    @MethodSource("happyPath")
    void getFoo_validRequest_returns2xx(...) {
        // GIVEN url + headers + body
        // WHEN  restTemplate.exchange(...)
        // THEN  assert status + body shape (AssertJ)
    }

    @ParameterizedTest
    @MethodSource("failurePath")
    void getFoo_failureTrigger_returnsMappedErrorStatus(final String input, final HttpStatus expectedStatus) {
        // assert status code mapping is correct
    }
}
```

The reference implementation is `FooComponentTest` – use it as
the canonical template.

### 3. Test resources

- `src/test/resources/application-component-test.yaml` contains **only**
  properties that differ from `src/main/resources/application.yaml`. Keep it
  tiny – Spring loads it on top of the main file when the `component-test`
  profile is active. Never name it `application.yaml`: a test-classpath
  `application.yaml` *replaces* the main one (same resource name), so every
  property the test file omits (e.g. `${kafka.topics…}` placeholders) is
  missing and the context fails to start.
- Place binary fixtures under
  `src/test/resources/<descriptive-folder>/`. Load them via a single
  `TestsResourcesHolder` (singleton) so multiple component tests share the
  fixture cache.

## Test design rules

1. **One component test class per use case** (= per `Operation` /
   public endpoint family). Do not lump unrelated endpoints together.
2. **Drive through HTTP only** – never call beans directly. The component
   test exists to prove the wiring (filters, security, advice, codecs) works.
3. **Cover all HTTP status branches**: 2xx happy path, 4xx (`400`, `403`,
   `404`, `409`, `415`, `422` as applicable), 5xx (`500` for unhandled,
   `503` for downstream-unavailable). Use a parameterised list keyed on the
   input that triggers each branch via `ComponentTestConfiguration`'s
   deterministic mocks.
4. **Assert on the response contract**: status, headers your clients depend
   on (e.g. `Content-Type`, `Content-Disposition`), and the body shape – not
   the internal bean state.
5. **Do not snapshot binary bodies byte-for-byte** unless the service guarantees
   it. Assert `body != null` + size > 0 + content-type instead.
6. **No `Thread.sleep`** – use Awaitility or readiness probes if the path is
   asynchronous.

## `@MockitoBean` vs `@TestConfiguration` — decision matrix

> **Spring Boot 3.4+ (the toolkit targets 3.5):** use Spring Framework 6.2's `@MockitoBean` / `@MockitoSpyBean`.
> The legacy `@MockBean` / `@SpyBean` are deprecated since 3.4 and removed in Boot 4.0; read any remaining
> `@MockBean` in older code as `@MockitoBean`. The rules below are unchanged.

| Use `@MockitoBean` directly in the test class when… | Use `@TestConfiguration` (this skill's default) when… |
| --- | --- |
| Only one test method needs the override | Multiple test classes share the same fakes |
| The stub differs per test | The stub is deterministic (branches on input) |
| The override is a Mockito-only mock | The override is a custom test bean (e.g. fake clock, fake clock-controlled scheduler) |

Avoid mixing both in the same module — pick one canonical place per
override. In `*ComponentTest` classes the right-hand column always applies
(see Do / Don't); the left-hand column is for slice tests (`@WebMvcTest`,
`@DataJpaTest`) that build their own small context. Each distinct set of
`@MockitoBean`s is part of the context cache key, so every class with a
different mock set starts (and caches) a new context (slow);
`@TestConfiguration` shared by all classes reuses one cached context.

## Authenticated paths

If your service requires authentication and you want to **test the secured
controller pipeline** (not bypass it via a permissive filter chain), use
Spring Security's request post-processors instead of disabling security.
This is a **separate security test, not a component test**: it runs
**without** the `component-test` profile (so the production filter chain is
active) and drives the controller through `MockMvc`. It is a `@WebMvcTest`
slice, so no real downstream starts: the controller's collaborator is a
`@MockitoBean` (slice tests are the left-hand column of the matrix above).
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
@Import(SecurityConfig.class)              // the production filter chain
class FooSecurityTest {
    @Autowired MockMvc mvc;
    @MockitoBean FooOperation fooOperation; // the controller's only collaborator
    @MockitoBean JwtDecoder jwtDecoder;     // jwt() bypasses it; the resource-server config still needs the bean

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

## Response-body assertions — JsonPath

For JSON responses, prefer JsonPath assertions over deserializing the body
into a DTO that mirrors the contract (which double-counts the test):

```java
mvc.perform(get("/api/v1/foo/123"))
   .andExpect(status().isOk())
   .andExpect(jsonPath("$.id").value("123"))
   .andExpect(jsonPath("$.items.length()").value(3))
   .andExpect(jsonPath("$.items[*].status", everyItem(equalTo("READY"))));
```

For `TestRestTemplate` (no `MockMvc`), request the body as a `String`
(`restTemplate.exchange(url, GET, HttpEntity.EMPTY, String.class)`) and
assert with AssertJ + JsonPath (`com.jayway.jsonpath`, in `spring-boot-starter-test`):

```java
assertThat(response.getBody()).isNotNull();
DocumentContext json = JsonPath.parse(response.getBody());
assertThat(json.<String>read("$.id")).isEqualTo("123");
```

## Snapshot / golden-file pattern

When the response is a large stable JSON / XML document (e.g. an export
endpoint), assert against a **golden file** in
`src/test/resources/__snapshots__/` rather than inlining the expected text:

```java
String actual   = response.getBody();
String expected = TestsResourcesHolder.getInstance().readString("__snapshots__/foo-export-happy.json");
JSONAssert.assertEquals(expected, actual, JSONCompareMode.LENIENT);
```

`readString` is a small helper on the `TestsResourcesHolder` from the Layout
(read the classpath resource as UTF-8). There is no built-in update switch:
update a snapshot intentionally by overwriting the file with the new
response, then review the diff in the PR. Snapshots make contract drift visible.

## Resetting state between tests

Component tests share a Spring context for speed. **Reset any mutable bean
state explicitly** in `@AfterEach` rather than reaching for
`@DirtiesContext` (which evicts the context and slows the suite to a
crawl):

```java
@AfterEach
void resetMocks(@Autowired PermissionsHandler ph) {
    Mockito.clearInvocations(ph);   // for @MockitoBean / @Primary mocks
}
```

Use `clearInvocations`, **not** `Mockito.reset(...)`: `reset` also wipes the
deterministic `doAnswer(...)` stubbing that `ComponentTestConfiguration`
installs once at bean creation, so every later test would see a do-nothing
mock.

```java
// ❌ wipes the shared deterministic stubbing
Mockito.reset(ph);
```

For real-bean state (caches, in-memory queues), expose a `void clear()`
method on the bean and call it in `@AfterEach` — never depend on the next
test cleaning up after the previous one.

## Maven / CI

- Component tests run under Surefire alongside unit tests by default.
  If they are slow, isolate them with the `*ComponentTest` Failsafe pattern
  and a `it` Maven profile: add `**/*ComponentTest.java` to the Failsafe
  `<includes>` (and to the Surefire `<excludes>`) — Failsafe's default
  includes only match `*IT` / `IT*` / `*ITCase`, so without it they never run.
- Tag any expensive test with `@Tag("component")` so CI can shard.

## Do / Don't

✅ Put every test-only bean override in `ComponentTestConfiguration` – never
inline `@MockitoBean` in the test class (hard to share, slow context restart).
✅ Branch fake behaviour on input (`fileId.equals("item-id-forbidden")`)
to keep a single config across many parameterised cases.
✅ Use `@LocalServerPort` + `MessageFormat` to build URLs – never hard-code
the port.
❌ Never enable real authentication in component tests – use the permissive
filter chain shown above (prove the security wiring in a separate
`*SecurityTest`, see "Authenticated paths").
❌ Never mock the controller, the operation, or the service – mock at the
**boundary** (clients, file store, permission handler).
❌ Never reach into a real database / message broker from a component test –
replace it with an in-process fake so component tests run on a laptop with
no infra. Anything that needs a real Testcontainer is an `*IT` integration
test (`integration-tests`), never part of `mvn test`.

## 4. Templates

- [`ComponentTest.java.tmpl`](./templates/ComponentTest.java.tmpl) — Ready-to-fill component test skeleton.
- [`ComponentTestConfiguration.java.tmpl`](./templates/ComponentTestConfiguration.java.tmpl) — Standard test configuration for component tests.

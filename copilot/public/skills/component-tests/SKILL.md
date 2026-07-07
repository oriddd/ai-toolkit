---
name: component-tests
description: Generate Spring Boot component (slice) tests that boot the full application context with a dedicated test profile, replace external collaborators (HTTP clients, file stores, permission handlers) with deterministic test doubles, and exercise the public HTTP API end-to-end via TestRestTemplate. Use when adding a new REST endpoint or use case to a microservice.
tier: must
applies_to: [rest, monolith]
depends_on: [unit-tests]
ships_templates: true
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# this Component Tests Skill

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
├── application.yaml                       # test-friendly defaults
└── <fixtures>/                            # binary / text fixtures
```

## Required pieces

### 1. `ComponentTestConfiguration`

A `@TestConfiguration` annotated with `@Profile("component-test")` that:

- Disables real security: provides a `SecurityFilterChain` bean that calls
  `httpSecurity.csrf(disable).authorizeHttpRequests(auth -> auth.anyRequest().permitAll())`.
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
component test pays the cost. Example from this repo:

```java
@TestConfiguration
@Profile("component-test")
public class NoHeavyStartupTestConfig {
    @Bean @Primary
    public HeavyStartupOrchestrator licensesLoadingOrchestrator() {
        return mock(HeavyStartupOrchestrator.class); // @PostConstruct is never run
    }
}
```

Import it alongside `ComponentTestConfiguration` via `@Import({…, …})`.

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
    void successfulCall(...) {
        // GIVEN url + headers + body
        // WHEN  restTemplate.exchange(...)
        // THEN  assert status + body shape
    }

    @ParameterizedTest
    @MethodSource("failurePath")
    void failingCall(final String input, final HttpStatus expectedStatus) {
        // assert status code mapping is correct
    }
}
```

The reference implementation is `FooComponentTest` – use it as
the canonical template.

### 3. Test resources

- `src/test/resources/application.yaml` contains **only** properties that
  differ from `src/main/resources/application.yaml`. Keep it tiny – Spring
  merges the two.
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

## `@MockBean` vs `@TestConfiguration` — decision matrix

| Use `@MockBean` directly in the test class when… | Use `@TestConfiguration` (this skill's default) when… |
| --- | --- |
| Only one test method needs the override | Multiple test classes share the same fakes |
| The stub differs per test | The stub is deterministic (branches on input) |
| The override is a Mockito-only mock | The override is a custom test bean (e.g. fake clock, fake clock-controlled scheduler) |

Avoid mixing both in the same module — pick one canonical place per
override. `@MockBean` forces the Spring context to refresh between test
classes (slow); `@TestConfiguration` reuses the cached context.

## Authenticated paths

If your service requires authentication and you want to **test the secured
controller pipeline** (not bypass it via a permissive filter chain), use
Spring Security's request post-processors instead of disabling security:

```java
@SpringBootTest @AutoConfigureMockMvc
class FooSecureComponentTest {
    @Autowired MockMvc mvc;

    @Test
    void requiresAuthenticatedJwt() throws Exception {
        mvc.perform(get("/api/v1/foo/123"))
           .andExpect(status().isUnauthorized());
    }

    @Test
    void allowsCallerWithRequiredScope() throws Exception {
        mvc.perform(get("/api/v1/foo/123")
                .with(jwt().jwt(b -> b.subject("alice")).authorities(new SimpleGrantedAuthority("SCOPE_FileAccess"))))
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

For `TestRestTemplate` (no `MockMvc`), assert with AssertJ + Jackson:

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
String expected = readResource("__snapshots__/foo-export-happy.json");
JSONAssert.assertEquals(expected, actual, JSONCompareMode.LENIENT);
```

Update the snapshot intentionally (e.g. `mvn -Dsnapshot.update=true test`),
then review the diff in the PR. Snapshots make contract drift visible.

## Resetting state between tests

Component tests share a Spring context for speed. **Reset any mutable bean
state explicitly** in `@AfterEach` rather than reaching for
`@DirtiesContext` (which evicts the context and slows the suite to a
crawl):

```java
@AfterEach
void resetMocks(@Autowired PermissionsHandler ph) {
    Mockito.reset(ph);     // for @MockBean / @Primary mocks
}
```

For real-bean state (caches, in-memory queues), expose a `void clear()`
method on the bean and call it in `@AfterEach` — never depend on the next
test cleaning up after the previous one.



- Component tests run under Surefire alongside unit tests by default.
  If they are slow, isolate them with the `*ComponentTest` Failsafe pattern
  and a `it` Maven profile.
- Tag any expensive test with `@Tag("component")` so CI can shard.

## Do / Don't

✅ Put every test-only bean override in `ComponentTestConfiguration` – never
inline `@MockBean` in the test class (hard to share, slow context restart).
✅ Branch fake behaviour on input (`fileId.equals("item-id-forbidden")`)
to keep a single config across many parameterised cases.
✅ Use `@LocalServerPort` + `MessageFormat` to build URLs – never hard-code
the port.
❌ Never enable real authentication in component tests – use the permissive
filter chain shown above.
❌ Never mock the controller, the operation, or the service – mock at the
**boundary** (clients, file store, permission handler).
❌ Never reach into the database / message broker without a Testcontainer
fake – component tests must run on a laptop with no infra.

## 4. Templates

- [`ComponentTest.java.tmpl`](./templates/ComponentTest.java.tmpl) — Ready-to-fill component test skeleton.
- [`ComponentTestConfiguration.java.tmpl`](./templates/ComponentTestConfiguration.java.tmpl) — Standard test configuration for component tests.

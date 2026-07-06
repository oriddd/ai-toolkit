---
name: unit-tests
description: Generate meaningful, high-coverage JUnit 5 + Mockito unit tests for Spring Boot classes. Use whenever a new class is created in src/main/java or whenever coverage on an existing class is below the Jacoco threshold. Produces tests that exercise happy path, every error/exception branch, and edge cases — not just line coverage.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: [code-structure]
ships_templates: true
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# this Unit Tests Skill

Generate **meaningful** unit tests (not coverage-padding) for any class under
`src/main/java`. Tests live in the mirror package under `src/test/java`.

## When to invoke

- A new class was added to `src/main/java` and has no matching `*Test.java`.
- Jacoco reports < 85% line / < 75% branch coverage for a class.
- A bug fix landed without a regression test.

## Test framework conventions (Project-wide)

- **JUnit 5** (`org.junit.jupiter.api.*`) – never JUnit 4.
- **Mockito** with `@ExtendWith(MockitoExtension.class)` and field injection
  via `@Mock` / `@InjectMocks`. Use constructor injection in `src/main` so
  Mockito wires automatically.
- **AssertJ or Jupiter `Assertions`** – pick one per repo and stay consistent
  (this repo uses Jupiter `Assertions`).
- Parameterised cases via `@ParameterizedTest` + `@MethodSource` /
  `@ValueSource` / `@CsvSource`. Group inputs in a `record` when each case
  carries multiple fields (see `FooServiceTest.ExceptionTestCase`).
- Test method names use the convention
  `<state>_<action>_<expectedOutcome>()` or the BDD style
  `when<Condition>_<Then>()`. Be descriptive – no `test1`, `test2`.
- Arrange / Act / Assert comments (`// given`, `// when`, `// then`) when the
  test has more than a handful of lines.
- For static method mocking use `try (MockedStatic<X> m = mockStatic(X.class))`
  inside the test method – never as a class field.

## Coverage goals (meaningful, not just lines)

For every non-trivial method you must cover, **at minimum**:

1. **Happy path** – one assertion per observable side-effect (return value,
   collaborator interaction, header set, exception swallowed, …).
2. **Every thrown exception type** declared on the method, plus
   `RuntimeException` for unchecked paths. Use a parameterised "exception
   provider" stream when more than two are involved.
3. **Every `if`/`switch` branch**, including `null` / empty-collection inputs
   if the method accepts collections or nullable params.
4. **Short-circuit / propagation behaviour** – when a collaborator throws,
   verify subsequent collaborators were `never()` called (see
   `FooServiceTest#whenPermissionsHandlerThrowsException…`).
5. **Boundary values** – min / max / empty / one-element / many-elements,
   `Optional.empty()` vs `Optional.of(...)`, case sensitivity flags.

If a class has no logic (pure DTO / record / `@Getter` Lombok holder) –
**do not generate a test**. Add it to `jacoco-maven-plugin`'s `<excludes>`
instead.

## Mocking rules

- Mock **only direct collaborators**. Never mock the class under test, never
  mock value objects.
- Stub the minimum needed for the assertion. Avoid
  `when(...).thenReturn(...)` chains that the test does not read.
- Use `verify(mock, times(n))` / `never()` / `verifyNoInteractions(mock)` to
  pin the **interaction contract**, not just the return value.
- Prefer `ArgumentCaptor` over loose `any()` when asserting that the correct
  object was passed to a collaborator.
- Reset shared static mocks between tests with `clearInvocations(mock)` in
  `@AfterEach` (see `FooServiceTest`).

## Static / context mocking

When the code under test calls a static method (e.g.
`SecurityContextHolder.getContext()`, `FilenameUtils.getExtension(...)`):

```java
try (MockedStatic<SecurityContextHolder> ctx = mockStatic(SecurityContextHolder.class)) {
    ctx.when(SecurityContextHolder::getContext).thenReturn(mockSecurityContext);
    // …act + assert…
}
```

Rules:
- **`try-with-resources` inside the test method** — never a class field, or
  the static stub leaks between tests and breaks parallel execution.
- One `MockedStatic` per class being statically stubbed.
- Reference: `PermissionsHandlerTest`.

## Testing `@PostConstruct` / heavy startup logic

If the class under test does work in `@PostConstruct` (license loading, cache
priming, big thread pools) and the unit test does **not** need that work,
construct the bean manually (no Spring context) and avoid invoking the init
method. For tests that **do** need a Spring slice, provide an opt-out
`@TestConfiguration` that replaces the bean with a no-op — see
`NoHeavyStartupTestConfig` and the `component-tests`
skill.

## Algorithm

For each target class `Foo`:

1. **Discover collaborators** – inspect constructor params of `Foo`. Each one
   becomes a `@Mock`.
2. **Enumerate public methods** – ignore Lombok-generated, `equals/hashCode/toString`.
3. **For every method, list branches** by re-reading the source:
   - thrown exceptions in signature → one test each.
   - `if`/`else`, `switch`, ternary, `Optional.orElseThrow` → one test each.
   - `Collection.isEmpty()` / `null` guards → one test each.
   - any `Stream.filter(...).findFirst()` → "found" + "not found" tests.
4. **Generate `FooTest`** in the mirror package using the
   [`templates/UnitTest.java.tmpl`](./templates/UnitTest.java.tmpl) skeleton.
5. **Run** `mvn -q -pl . test -Dtest=FooTest jacoco:report`. Open
   `target/site/jacoco/<package>/Foo.html` and add tests for any remaining
   uncovered branch. Iterate until you cannot meaningfully cover more.
6. **Sanity check** – delete each generated test one-by-one mentally: if the
   class would still pass `mvn verify` after deletion, the test is not
   meaningful and should be removed/strengthened.

## Assertions — AssertJ (default)

Prefer **AssertJ** (`org.assertj:assertj-core`, transitive via
`spring-boot-starter-test`) over Jupiter `Assertions` for everything except
the simplest `assertEquals`. AssertJ produces dramatically better failure
messages and is fluent:

```java
assertThat(result).isNotNull()
    .extracting(Foo::id, Foo::status)
    .containsExactly("x-1", Status.READY);

assertThat(list).hasSize(3).extracting(Foo::id).containsExactly("a","b","c");

assertThatThrownBy(() -> svc.fail()).isInstanceOf(FooException.class)
    .hasMessageContaining("not allowed");

// soft assertions: collect all failures before reporting
assertSoftly(s -> {
    s.assertThat(foo.id()).isEqualTo("x-1");
    s.assertThat(foo.status()).isEqualTo(Status.READY);
});
```

Use `assertSoftly` whenever a test verifies several independent
post-conditions; one run, all failures visible.

## Test Data Builders

For any DTO / record with > 3 fields, write a **builder** in
`src/test/java/.../testdata/` so tests stay readable:

```java
public final class FooRequestTestBuilder {
    private String id    = "id-default";
    private String value = "value-default";
    private FooRequestTestBuilder() {}
    public static FooRequestTestBuilder aFooRequest() { return new FooRequestTestBuilder(); }
    public FooRequestTestBuilder withId(String s)    { this.id = s; return this; }
    public FooRequestTestBuilder withValue(String s) { this.value = s; return this; }
    public FooRequest build() { return new FooRequest(id, value); }
}

// usage
var req = aFooRequest().withId("specific").build();
```

Tests then read like English; the builder absorbs DTO changes (one place to
edit when a field is added).

## Parameterized variants

| Annotation | When |
| --- | --- |
| `@ValueSource(strings = {…})` | Single primitive / string axis |
| `@CsvSource("a,1", "b,2")` | Two-three columns of inline data |
| `@CsvFileSource(resources = "/cases.csv", numLinesToSkip = 1)` | Many cases / business sourced data |
| `@EnumSource(MyEnum.class)` | All enum values, or a subset via `names = ...` |
| `@MethodSource` | Anything Java can produce — most flexible |
| `@ArgumentsSource(MyProvider.class)` | Reusable cases across multiple tests |

Prefer the **most specific** that fits; reach for `@MethodSource` only when
the others don't suffice.

## Mutation testing — the real coverage gate

Line coverage measures **execution**, not **verification**. Add
[PIT](https://pitest.org/) to measure whether your assertions catch
seeded bugs:

```xml
<plugin>
    <groupId>org.pitest</groupId>
    <artifactId>pitest-maven</artifactId>
    <version>1.16.0</version>
    <executions><execution><goals><goal>mutationCoverage</goal></goals></execution></executions>
    <configuration>
        <targetClasses><param>{{basePackage}}.*</param></targetClasses>
        <mutationThreshold>75</mutationThreshold>
    </configuration>
</plugin>
```

`mvn org.pitest:pitest-maven:mutationCoverage` produces an HTML report
showing which mutants **survived** — those are tests that line up to
exercise the code but never assert on its result. Fix the test, not the
threshold.

## Architecture tests (ArchUnit)

The package-hierarchy + design-pattern rules from `code-structure` are
verified by an ArchUnit test class committed to `src/test/java`. See the
ArchUnit section of the `code-structure` skill for the canonical rules. The
test runs under Surefire — a layering violation breaks the build.

## HTTP client tests — WireMock / MockWebServer

When unit-testing a `*Client` from the `external-client` skill, stub the
HTTP boundary with **MockWebServer** (OkHttp) or **WireMock**:

```java
class FooDependencyClientTest {
    static MockWebServer server;
    @BeforeAll static void up()   throws Exception { server = new MockWebServer(); server.start(); }
    @AfterAll  static void down() throws Exception { server.shutdown(); }

    @Test
    void deserializesAndUnwrapsHits() {
        server.enqueue(new MockResponse().setBody("""{"hits":[{"id":"x"}]}""")
                .addHeader("Content-Type","application/json"));

        var client = new FooDependencyClient(
            WebClient.builder().baseUrl(server.url("/").toString()).build(), "/api");

        assertThat(client.simpleSearch(new Request("x")).getBody().getHits())
            .extracting(Hit::id).containsExactly("x");
    }

    @Test
    void translatesNon2xxToDomainException() {
        server.enqueue(new MockResponse().setResponseCode(500));
        var client = new FooDependencyClient(...);
        assertThatThrownBy(() -> client.simpleSearch(new Request("x")))
            .isInstanceOf(FooException.class);
    }
}
```

Slow / cross-process integration variants belong in the `integration-tests`
skill, not here.

## Property-based testing (when applicable)

For pure functions with a large input space (parsers, format converters,
serializers), add a **jqwik** test:

```xml
<dependency>
    <groupId>net.jqwik</groupId>
    <artifactId>jqwik</artifactId>
    <version>1.9.0</version>
    <scope>test</scope>
</dependency>
```

```java
@Property
boolean roundTripsAnyAscii(@ForAll @AlphaChars String s) {
    return Codec.decode(Codec.encode(s)).equals(s);
}
```

jqwik **shrinks** counter-examples automatically — failure messages point
at the minimal input that breaks the property.

- Strategy pattern: `PermissionsHandlerTest` – shows `MockedStatic`,
  list-injection, multiple branch tests.
- Service with collaborators: `FooServiceTest` – shows record-based
  parameterised exception provider, `clearInvocations`, propagation checks.
- Operation orchestration: `FooOperationTest` – shows
  `verifyNoInteractions` to assert short-circuit behaviour.

## Do / Don't

✅ One assertion concept per test; many `assertEquals` are fine if they all
verify the same logical outcome.
✅ Use `record` test-case holders for parameterised tests.
✅ Co-locate test fixtures under `src/test/java/.../testdata/`.
✅ Wire Jacoco quality gates in `pom.xml` so coverage regressions break the build.
❌ Never write a test whose only assertion is `assertNotNull(result)` on a
non-null-returning method – that proves nothing.
❌ Never assert on log lines unless logging *is* the contract.
❌ Never use `Thread.sleep` – use Awaitility for async waits.
❌ Never share mutable state between tests without `@AfterEach` cleanup.

  - [ ] Add PIT mutation testing for core logic.
  - [ ] Integrate Jacoco check with a line coverage threshold (e.g., 80%).

## 6. Architecture Tests (ArchUnit)

Unit tests are not just for business logic; they also protect the **structure** of your code. ArchUnit allows you to write tests that ensure design patterns are followed.

### Example: Enforce Strategy + Handler Pattern

```java
@ArchTest
static final ArchRule strategiesMustLiveInSpecificPackage =
    classes().that().implement(XyzStrategy.class)
        .should().resideInAPackage("..converter.strategy..")
        .andShould().haveSimpleNameEndingWith("Strategy");
```

### Example: Prevent Layer Leaks

```java
@ArchTest
static final ArchRule servicesMustNotDependOnControllers =
    noClasses().that().resideInAPackage("..service..")
        .should().dependOnClassesThat().resideInAPackage("..controller..");
```

See the `code-structure` skill for more examples. Always include an `ArchitectureTest.java` in your project to turn conventions into build failures.

## 7. Templates

- [`UnitTest.java.tmpl`](./templates/UnitTest.java.tmpl) — Standard Mockito unit test skeleton.

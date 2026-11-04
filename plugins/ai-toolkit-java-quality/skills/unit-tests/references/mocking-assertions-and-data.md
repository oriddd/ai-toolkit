# this Unit Tests Skill — Mocking, assertions and test data

Part of the [`unit-tests`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

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

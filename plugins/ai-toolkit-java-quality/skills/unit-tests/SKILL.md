---
name: unit-tests
description: Generate meaningful, high-coverage JUnit 5 + Mockito unit tests for Spring Boot classes. Use whenever a new class is created in src/main/java or whenever coverage on an existing class is below the Jacoco threshold. Produces tests that exercise happy path (positive tests), every error/exception branch (negative tests), and edge cases — not just line coverage. Follows methodName_Condition_ExpectedResult naming convention.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: [code-structure, testable-code-principles]
ships_templates: true
hitl: false
version: 1.1
last_reviewed: 2026-07-12
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

## Reference map — load only the part you are working on

Sections below keep their numbers but live in `references/` so this file stays small. Read only the file you need; do not load them all.

| Sections | Topic | Load when | File |
| --- | --- | --- | --- |
| Test Every LEGO Brick | worked tests per layer | writing tests for a specific kind of class | [`per-layer-tests.md`](./references/per-layer-tests.md) |
| Mocking rules … Parameterized variants | mocking and static mocking, `@PostConstruct`, AssertJ, test data builders, parameterized tests | choosing mocks, assertions or test-data builders | [`mocking-assertions-and-data.md`](./references/mocking-assertions-and-data.md) |
| Mutation testing … Property-based testing | PIT, ArchUnit, WireMock / MockWebServer, jqwik | the change touches an HTTP client, needs mutation testing or property tests | [`mutation-http-and-property-tests.md`](./references/mutation-http-and-property-tests.md) |

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
        .should().resideInAPackage("..renderer.strategy..")
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

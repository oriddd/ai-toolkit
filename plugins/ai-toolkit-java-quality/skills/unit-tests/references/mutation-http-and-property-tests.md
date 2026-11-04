# this Unit Tests Skill — Mutation, HTTP client and property-based tests

Part of the [`unit-tests`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## Mutation testing — the real coverage gate

Line coverage measures **execution**, not **verification**. Add
[PIT](https://pitest.org/) to measure whether your assertions catch
seeded bugs:

```xml
<plugin>
    <groupId>org.pitest</groupId>
    <artifactId>pitest-maven</artifactId>
    <version>1.16.0</version>
    <dependencies>
        <!-- without this PIT finds no JUnit 5 tests and the mutation gate silently measures nothing -->
        <dependency>
            <groupId>org.pitest</groupId>
            <artifactId>pitest-junit5-plugin</artifactId>
            <version>1.2.1</version>
        </dependency>
    </dependencies>
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
        server.enqueue(new MockResponse().setBody("{\"hits\":[{\"id\":\"x\"}]}")
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

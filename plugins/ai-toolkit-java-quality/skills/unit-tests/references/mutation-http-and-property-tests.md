# Unit Tests Skill — Mutation, HTTP client and property-based tests

Part of the [`unit-tests`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## Mutation testing — the real coverage gate

Line coverage measures **execution**, not **verification**. Add
[PIT](https://pitest.org/) to measure whether your assertions catch
seeded bugs. PIT is **required** (guild #12: mutation score ≥ 75 %); the `ci` skill's
`pom.xml.tmpl` already wires exactly this block into `verify`:

```xml
<plugin>
    <groupId>org.pitest</groupId>
    <artifactId>pitest-maven</artifactId>
    <version>1.20.0</version>   <!-- 1.16 + junit5-plugin 1.2.1 fail on JUnit 5.12 (Boot 3.5) -->
    <dependencies>
        <!-- without this PIT finds no JUnit 5 tests and the mutation gate silently measures nothing -->
        <dependency>
            <groupId>org.pitest</groupId>
            <artifactId>pitest-junit5-plugin</artifactId>
            <version>1.2.3</version>
        </dependency>
    </dependencies>
    <executions><execution><id>pit</id><phase>verify</phase><goals><goal>mutationCoverage</goal></goals></execution></executions>
    <configuration>
        <targetClasses><param>{{basePackage}}.*</param></targetClasses>
        <excludedClasses>
            <param>{{basePackage}}.generated.*</param>   <!-- openapi-generated code -->
            <param>{{basePackage}}.*Application</param>
        </excludedClasses>
        <!-- unit tests only: Spring-context and container tests are far too slow to run per mutant -->
        <excludedTestClasses>
            <param>*IT</param>
            <param>*ComponentTest</param>
            <param>*ArchitectureTest</param>
        </excludedTestClasses>
        <mutationThreshold>75</mutationThreshold>
        <failWhenNoMutations>false</failWhenNoMutations>   <!-- a fresh skeleton has nothing to mutate -->
        <withHistory>true</withHistory>                    <!-- incremental: unchanged classes reuse the last result -->
    </configuration>
</plugin>
```

`mvn org.pitest:pitest-maven:mutationCoverage` produces an HTML report
showing which mutants **survived** — those are tests that line up to
exercise the code but never assert on its result. Fix the test, not the
threshold.

For a fast local loop skip it with `-DskipPitest` (not `-Dpit.skip`); CI always runs it.

## Architecture tests (ArchUnit)

The package-hierarchy + design-pattern rules from `code-structure` are
verified by an ArchUnit test class committed to `src/test/java`. See the
ArchUnit section of the `code-structure` skill for the canonical rules. The
test runs under Surefire — a layering violation breaks the build.

## HTTP client tests — WireMock / MockWebServer

When unit-testing a `*Client` from the `external-client` skill, stub the HTTP boundary — never mock `RestClient` /
`WebClient` method by method. Pick the stub by transport:

- **`RestClient`** (`external-client` §6): Spring's `MockRestServiceServer` bound to the `RestClient.Builder`
  (`spring-test`, already in `spring-boot-starter-test` — no extra dependency). The example below.
- **`WebClient`**, or a test that needs a real socket (connect / read timeouts of the configured request factory):
  **WireMock** (same dependency as `integration-tests`) or **MockWebServer** (OkHttp — not managed by the Spring
  Boot BOM, so declare `com.squareup.okhttp3:mockwebserver` explicitly; OkHttp 5 moved it to `mockwebserver3`).

The client is built exactly as in `external-client`: constructor `(RestClient, FooProperties)`, failures mapped to
the shared catalogue (`UnavailableException` for 5xx and timeouts, `DependencyException` for other non-2xx —
`exception-handling`); the request DTO is the setter-based `FooSearchRequestDto`:

```java
class FooClientTest {
    private MockRestServiceServer server;
    private FooClient client;

    @BeforeEach
    void setUp() {
        final RestClient.Builder builder = RestClient.builder().baseUrl("http://foo");
        server = MockRestServiceServer.bindTo(builder).build();
        client = new FooClient(builder.build(), new FooProperties("http://foo", "/api/search",
                new FooProperties.Timeouts(Duration.ofSeconds(1), Duration.ofSeconds(2))));
    }

    private static FooSearchRequestDto searchFor(final String queryId) {
        final FooSearchRequestDto request = new FooSearchRequestDto();
        request.setQueryId(queryId);
        return request;
    }

    @Test
    void search_2xxResponse_returnsMappedHits() {
        server.expect(requestTo("http://foo/api/search")).andExpect(method(HttpMethod.POST))
                .andExpect(jsonPath("$.queryId").value("x"))
                .andRespond(withSuccess("{\"totalHits\":1,\"products\":[{\"id\":\"p-1\"}]}", MediaType.APPLICATION_JSON));

        final FooSearchResponseDto response = client.search(searchFor("x"));

        assertThat(response.getTotalHits()).isEqualTo(1);
        assertThat(response.getProducts()).extracting(FooProductDto::getId).containsExactly("p-1");
        server.verify();
    }

    @Test
    void search_5xxResponse_throwsUnavailableException() {
        server.expect(requestTo("http://foo/api/search")).andRespond(withServiceUnavailable());

        assertThatThrownBy(() -> client.search(searchFor("x"))).isInstanceOf(UnavailableException.class);
    }

    @Test
    void search_4xxResponse_throwsDependencyException() {
        server.expect(requestTo("http://foo/api/search")).andRespond(withBadRequest());

        assertThatThrownBy(() -> client.search(searchFor("x"))).isInstanceOf(DependencyException.class);
    }

    @Test
    void search_timeout_throwsUnavailableException() {
        server.expect(requestTo("http://foo/api/search"))
                .andRespond(withException(new SocketTimeoutException("read timed out")));

        assertThatThrownBy(() -> client.search(searchFor("x"))).isInstanceOf(UnavailableException.class);
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

## Worked examples to model on

Illustrative class names — map each to the matching test in your repo:

- Strategy pattern: `PermissionsHandlerTest` – shows `MockedStatic`,
  list-injection, multiple branch tests.
- Service with collaborators: `FooServiceTest` – shows record-based
  parameterised exception provider, `clearInvocations`, propagation checks.
- Operation orchestration: `FooOperationTest` – shows
  `verifyNoInteractions` to assert short-circuit behaviour.

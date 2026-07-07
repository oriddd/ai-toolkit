---
name: integration-tests
description: Drive a Spring Boot microservice against real downstream dependencies (DB, broker, S3-compatible object store, mocked HTTP) using Testcontainers, with strict Surefire/Failsafe segregation (unit vs component vs integration) and an opt-in contract-testing flow (Pact / Spring Cloud Contract). Use when component tests are insufficient because the behaviour under test depends on the actual semantics of a downstream system.
tier: should
applies_to: [rest, event, monolith]
depends_on: [component-tests]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Integration Tests Skill (public)

Component tests (see `component-tests`) drive the service via HTTP with
**in-process fakes** at the boundary. Integration tests drive the same
service with **real downstream systems** (or contract-faithful stubs).

| Test type | Boundary | Speed | When |
| --- | --- | --- | --- |
| Unit       | Single class, mocked collaborators       | < 100 ms | Every commit |
| Component  | Full app context, in-process fakes       | seconds  | Every commit |
| Integration | Full app context + Testcontainers / WireMock / real DB | tens of seconds | Pre-merge / nightly |
| Contract   | Producer + consumer agree on a wire spec | seconds  | On every change to a public API |

## Surefire / Failsafe split

- **Surefire** runs `**/*Test.java` → unit + component (fast).
- **Failsafe** runs `**/*IT.java` → integration (slow, may need Docker).

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-failsafe-plugin</artifactId>
    <configuration>
        <includes><include>**/*IT.java</include></includes>
    </configuration>
    <executions>
        <execution>
            <goals>
                <goal>integration-test</goal>
                <goal>verify</goal>
            </goals>
        </execution>
    </executions>
</plugin>
```

Combined with JUnit `@Tag`:

```java
@Tag("integration")
@Testcontainers
class FooRepositoryIT { ... }
```

In CI: `mvn verify` runs both Surefire and Failsafe; `mvn test` runs only
Surefire (fast inner loop).

## Testcontainers — real downstream

```xml
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>junit-jupiter</artifactId>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>postgresql</artifactId>
    <scope>test</scope>
</dependency>
```

```java
@SpringBootTest(webEnvironment = RANDOM_PORT)
@Testcontainers
@Tag("integration")
class FooRepositoryIT {

    @Container
    static PostgreSQLContainer<?> db = new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry reg) {
        reg.add("spring.datasource.url",      db::getJdbcUrl);
        reg.add("spring.datasource.username", db::getUsername);
        reg.add("spring.datasource.password", db::getPassword);
    }

    @Autowired FooRepository repo;

    @Test
    void persistsAndReads() {
        repo.save(new Foo("id-1", "hello"));
        assertThat(repo.findById("id-1")).hasValueSatisfying(f -> assertThat(f.value()).isEqualTo("hello"));
    }
}
```

Available canonical containers:
- `PostgreSQLContainer`, `MySQLContainer`, `MongoDBContainer`
- `KafkaContainer`, `RabbitMQContainer`
- `MinIOContainer`, `LocalStackContainer` (for S3/SQS/SNS)
- `GenericContainer` for anything else

Rules:
- **One container per `@Testcontainers` class** when possible.
- **Reuse** containers across the JVM with
  `.withReuse(true)` + `~/.testcontainers.properties: testcontainers.reuse.enable=true`
  to speed up local dev.
- **Never** rely on a fixed host port — always read the mapped port from the
  container.
- **Always tag** with `@Tag("integration")` so Failsafe picks them up and
  Surefire skips them.

## WireMock — contract-faithful HTTP stub

When the downstream is HTTP and a Testcontainer image does not exist (or is
too heavy), use **WireMock**:

```xml
<dependency>
    <groupId>org.wiremock</groupId>
    <artifactId>wiremock-standalone</artifactId>
    <scope>test</scope>
</dependency>
```

```java
@SpringBootTest(webEnvironment = RANDOM_PORT)
@Tag("integration")
class FooClientIT {

    static WireMockServer wm;

    @BeforeAll static void up()   { wm = new WireMockServer(0); wm.start(); }
    @AfterAll  static void down() { wm.stop(); }

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry reg) {
        reg.add("foo.dependency.base-url", () -> "http://localhost:" + wm.port());
    }

    @Autowired FooDependencyClient client;

    @Test
    void deserializesSuccessfulResponse() {
        wm.stubFor(post("/api").willReturn(okJson("""
            { "hits": [ { "id": "x" } ] }
            """)));

        assertThat(client.simpleSearch(new Request("x"))).isNotNull();
    }

    @Test
    void translatesNon2xxToDomainException() {
        wm.stubFor(post("/api").willReturn(serverError()));
        assertThatThrownBy(() -> client.simpleSearch(new Request("x")))
            .isInstanceOf(FooException.class);
    }
}
```

WireMock can **record** responses from a real instance via
`wm.startRecording(...)` — useful for capturing fixtures from a staging
environment once, then replaying them deterministically forever.

## Contract testing

When two teams own producer and consumer separately, replace ad-hoc HTTP
stubs with a shared **contract**:

### Option A — Spring Cloud Contract (Groovy DSL, JVM-only)

The producer writes contracts:
```groovy
Contract.make {
    request { method 'POST'; url '/api'; body([id: 'x']) }
    response { status OK(); body([hits:[[id:'x']]]) }
}
```
Build publishes a *stubs jar*; consumers depend on it and get a fully
configured WireMock instance via `@AutoConfigureStubRunner`.

### Option B — Pact (polyglot)

Consumer writes the expectation; pact file goes to a Pact Broker; producer
verifies on every build.

Pick **one** of the two per organization. Whichever is chosen:
- **Producer**: contract verification is a required CI step
  (`@PactVerification` / `@AutoConfigureStubRunner(stubsMode = LOCAL)`).
- **Consumer**: stub-based integration tests use the same contract artifact
  so the consumer cannot drift.

## Test data lifecycle

- **Never** rely on test ordering. Each `@Test` sets up and tears down its
  own data (`@BeforeEach` insert, `@AfterEach` delete) or runs inside a
  transaction that is rolled back (`@Transactional` on the test class).
- For schemas: `Flyway` / `Liquibase` migrations run automatically against
  the Testcontainer; never bypass them with ad-hoc DDL.

## CI integration

```
mvn -B test                          # fast — unit + component
mvn -B -Dgroups=integration verify   # slow — integration (requires Docker)
```

Make integration green a **required** check on `main`; do not block PRs on
it unless the changed code touched a `client/` package or a repository.

## Do / Don't

✅ Real DB / broker tests must use Testcontainers, never an embedded H2 /
embedded Kafka — those lie.
✅ Tag every integration test (`@Tag("integration")`) and name it `*IT.java`.
✅ Read mapped ports from the container; never assume a fixed port.
✅ Reset state per test, not per class.
❌ Never enable Testcontainers in `mvn test` — it makes the inner loop slow.
❌ Never commit Pact / Cloud-Contract artifacts as binaries — publish them.
❌ Never use both Spring Cloud Contract **and** Pact in the same
organization; the duplication is worse than either choice.


# Spring Boot 4.x — verified second target

Spring Boot **3.5.x stays the default** (`create-repo` Q7). Boot 4.1.x is a supported variant for the items below.
Evidence: a rendered service (ci `pom.xml.tmpl` with Error Prone 2.52 + NullAway 0.14.3 at ERROR on JDK 21, Application,
`application.yaml`, exception handling, permissions, `external-client` HTTP adapter, persistence, messaging, request-metrics,
graceful-shutdown, component tests, `ArchitectureTest`) was built on **3.5.16** and on **4.1.2** with the same sources.
Both: 26 tests green, zero NullAway errors. 4.1.2 resolved Spring Framework 7.0.10, Spring Security 7.1.2,
Hibernate 7.4.13, Jackson 3.1.7 (`tools.jackson`), Hibernate Validator 9.1.5, Spring Kafka 4.1.2, Micrometer 1.17.2,
Tomcat 11, JUnit 6, Testcontainers 2.0.5. Everything not listed under "Verified" is **not** verified on 4.x.

## Dual-compatible (the shipped template is valid on 3.5 and 4.x)

| Area | Change (already applied in the templates) | Why |
| --- | --- | --- |
| `GlobalExceptionHandler` | `@Nullable` on the overridden `handle…` return types and on `violation(...)` parameters | Spring 7 and Micrometer 1.17 are JSpecify-annotated; NullAway at ERROR then flags `getDefaultMessage()`, `handleExceptionInternal(...)` |
| `CacheClient` `store`/`evict` | `exchange` lambda returns `Boolean.TRUE` instead of `null` | NullAway: null returned from a non-null generic |
| Component-test DB exclusion | list the 3.5 **and** the 4.x auto-configuration class names in `spring.autoconfigure.exclude` | unknown names are ignored silently; with only the 3.5 names Boot 4 **starts the database anyway** (Hikari + H2 started in the component-test context until an assertion on the `DataSource` bean was added) |
| Graceful-shutdown test | `Objects.requireNonNull(...getWebServer())` | `getWebServer()` is `@Nullable` in 4.x |
| Null-safe tests | `Objects.requireNonNull(registry.find(..).timer())`, `hasToString(...)` instead of dereferencing `getContentType()` | same JSpecify effect in test code |

## Needs a 4.x variant (not expressible for both)

| Area | 3.5 | 4.x | Verified how |
| --- | --- | --- | --- |
| Parent | `spring-boot-starter-parent` 3.5.x | 4.1.x | built |
| Web starter | `spring-boot-starter-web` | `spring-boot-starter-web` still resolves (to `spring-boot-webmvc`); canonical name `spring-boot-starter-webmvc` | built with the old name |
| RestClient autoconfig | in `starter-web` | add `spring-boot-restclient` (starter `spring-boot-starter-restclient`); `RestClient.Builder` bean comes from it | compile + `HttpProviderTest` |
| HTTP client settings | `org.springframework.boot.http.client.ClientHttpRequestFactorySettings` | `org.springframework.boot.http.client.HttpClientSettings` (same `withConnectTimeout/withReadTimeout`; injected the same way) | compile + test of the HTTP cache adapter |
| Jackson | `com.fasterxml.jackson.databind.ObjectMapper`, `JsonProcessingException` | `tools.jackson.databind.ObjectMapper` / `JsonMapper`, `tools.jackson.core.JacksonException` (unchecked); annotations stay `com.fasterxml.jackson.annotation` | `ProblemDetailSecurityHandler` writes the 401/403/503 body, unit test `IdpHandlerTest` |
| Kafka | `spring-kafka`; `org.springframework.boot.autoconfigure.kafka.ConcurrentKafkaListenerContainerFactoryConfigurer` | `spring-boot-starter-kafka`; `org.springframework.boot.kafka.autoconfigure.…` | compile + context boot |
| `@RetryableTopic` | `backoff = @Backoff(delayExpression, multiplierExpression, maxDelayExpression)` from `org.springframework.retry.annotation` | `backOff = @BackOff(delayString, multiplierString, maxDelayString)` from `org.springframework.kafka.annotation` (spring-retry is gone) | compile of `DlqHandler` only; a retry/DLT run against a broker was **not** executed |
| Security filter order | `SecurityProperties.DEFAULT_FILTER_ORDER` (`org.springframework.boot.autoconfigure.security`) | `org.springframework.boot.security.autoconfigure.web.servlet.SecurityFilterProperties.DEFAULT_FILTER_ORDER` | request-metrics `MetricsFilter` compiled and recorded a timer through the filter chain |
| Auto-configuration class names | `org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration`, `.orm.jpa.HibernateJpaAutoConfiguration`, `.flyway.FlywayAutoConfiguration` | `org.springframework.boot.jdbc.autoconfigure.…`, `org.springframework.boot.hibernate.autoconfigure.…`, `org.springframework.boot.flyway.autoconfigure.…` | jar contents + component test asserting no `DataSource` bean |
| `TestRestTemplate` | in `spring-boot-starter-test` | dependency `spring-boot-resttestclient` (test), import `org.springframework.boot.resttestclient.TestRestTemplate`, annotate the test with `@AutoConfigureTestRestTemplate` (`…resttestclient.autoconfigure`) | component, context and metrics tests |
| `@LocalServerPort`, `@MockitoBean`, `@SpringBootTest` | as is | unchanged package; `@MockitoBean` stays | used by the tests above; add the `@LocalServerPort` FQN to NullAway `ExcludedFieldAnnotations` only if it moves |
| `WebServerApplicationContext` | `org.springframework.boot.web.context` | `org.springframework.boot.web.server.context` | graceful-shutdown component test (3 tests) |
| Testcontainers | 1.x: `org.testcontainers:postgresql`, `junit-jupiter`; `org.testcontainers.containers.PostgreSQLContainer<?>` | 2.x: `testcontainers-postgresql`, `testcontainers-junit-jupiter`; `org.testcontainers.postgresql.PostgreSQLContainer` (not generic); `@ServiceConnection` unchanged | `PersistenceIT` on Postgres 16 with Docker (Colima needs `DOCKER_HOST` and `TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock`) |
| JPA static metamodel | `hibernate-jpamodelgen` (managed) | `hibernate-jpamodelgen` is not managed by Boot 4's BOM; the artifact is `hibernate-processor` (managed, 7.4.13) | BOM resolution only: the jar could not be downloaded here, so the generated `Invoice_` classes were **not** built on 4.x |

## Verified without a change

Error Prone + NullAway configuration (same `compilerArgs`, `.mvn/jvm.config`), `application.yaml` incl. `server.shutdown: graceful`,
actuator health/liveness/readiness/prometheus endpoints, `spring-boot-starter-validation`, `-oauth2-resource-server`
(`JwtDecoder` mocked with `@MockitoBean`, `IdentityProviderUnavailableFilter`, `SecurityConfig`, `ProblemDetailSecurityHandler`),
`-data-jpa` (`BaseEntity`, `@EnableJpaAuditing` + `SecurityAuditorAware`, `OutboxEntity` against the outbox migration SQL with
`ddl-auto: validate` on Postgres 16), `micrometer-registry-prometheus`, Lombok, `ArchitectureTest` (ArchUnit 1.4.1, 8 rules),
the `component-test` profile with a no-op `PlatformTransactionManager`, `GlobalExceptionHandler` with its `handleExceptionInternal` override (404 / 405 / 415 carry `errorCode`; `@Nullable` return and `body` are valid on both Spring 6.2 and 7), request-metrics `Filter + Recorder + Parser`
(a recorder timer with generic and domain tags). The metrics filter records after the response is committed: a test that reads
the registry right after the HTTP call must poll (Awaitility), it passed alone and failed in a full run without it.

## Not verified on 4.x (do not assume)

Flyway on Postgres (`flyway-database-postgresql` 12.x not in the local cache), outbound OAuth2 client credentials
(`spring-boot-starter-oauth2-client` / Security 7 jars not available; the interceptor compiled on 3.5 only), springdoc,
`openapi-generator-maven-plugin` output, Resilience4j, Bucket4j, ShedLock, native `@Retryable` / `@ConcurrencyLimit`
(`org.springframework.resilience.annotation` exist in spring-context 7.0.10, but no behaviour was tested, so keep
Resilience4j as the documented choice), Kafka retry/DLT against a broker, Helm/Docker image, the Spotless, SpotBugs, JaCoCo
and PIT gates (the build ran `test` with Checkstyle in `validate`, not `verify`).
Network access to Maven Central was not used because the corporate mirror is the configured repository.

# Spring Boot 4.x — verified second target

Spring Boot **3.5.x stays the default** (`create-repo` Q7). Boot 4.1.x is a supported variant for the items below.
Evidence: a rendered service (ci `pom.xml.tmpl` with Error Prone 2.52 + NullAway 0.14.3 at ERROR on JDK 21, Application,
`application.yaml`, exception handling, permissions, `external-client` HTTP adapter, persistence, messaging, request-metrics,
graceful-shutdown, component tests, `ArchitectureTest`) was built on **3.5.16** and on **4.1.2** with the same sources.
Both: 26 tests green, zero NullAway errors. 4.1.2 resolved Spring Framework 7.0.10, Spring Security 7.1.2,
Hibernate 7.4.13, Jackson 3.1.7 (`tools.jackson`), Hibernate Validator 9.1.5, Spring Kafka 4.1.2, Micrometer 1.17.2,
Tomcat 11, JUnit 6, Testcontainers 2.0.5. Everything not listed under "Verified" or "Also verified" is **not** verified on 4.x.

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
| HTTP client settings | `org.springframework.boot.http.client.ClientHttpRequestFactorySettings` | `org.springframework.boot.http.client.HttpClientSettings` (same `withConnectTimeout/withReadTimeout`; `withRedirects(HttpRedirects.DONT_FOLLOW)` replaces `Redirects.DONT_FOLLOW`; injected the same way) | compile + test of the HTTP cache adapter |
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

## Also verified on 4.1.2 (second pass)

Run on Boot 4.1.2 with the same snippets, Docker containers where noted:

| Area | Result | 4.x difference |
| --- | --- | --- |
| Resilience4j 2.4.0 (retry + circuit breaker + fallback rethrowing checked domain exceptions, semaphore and thread-pool bulkhead, `@TimeLimiter`, `@RateLimiter`) | 12 tests green | starter is `io.github.resilience4j:resilience4j-spring-boot4` with an explicit `<version>` (not in `resilience4j-bom`) plus `spring-boot-starter-aspectj`; `resilience4j-spring-boot3` stops the application with `IncompatibleSpringBootVersionException`; auto-configuration packages are `io.github.resilience4j.springboot.*` |
| Bucket4j 8.22.0 local + Redis (`RateLimiterPort` contract, two pods on one bucket, Redis 7 container) | 5 tests green | none; Testcontainers `GenericContainer` unchanged |
| Outbound OAuth2 client credentials (`external-client` §6b: token fetched once, cached, refreshed near expiry, replaced after a 401, token-endpoint failure → `UnavailableException`) | 7 tests green against a stub token endpoint and API | `spring-boot-starter-oauth2-client` + `spring-boot-starter-restclient`; `HttpClientSettings`; test imports `org.springframework.boot.security.oauth2.client.autoconfigure.OAuth2ClientAutoConfiguration`, `org.springframework.boot.restclient.autoconfigure.RestClientAutoConfiguration`, `org.springframework.boot.http.client.autoconfigure.HttpClientAutoConfiguration` **and** `…imperative.ImperativeHttpClientAutoConfiguration` (it provides the `ClientHttpRequestFactoryBuilder` bean) |
| Transactional outbox + Kafka (`messaging`: rollback atomicity, restart, crash between ack and mark, broker paused, dedupe by `event-id`, ShedLock 6.10.0) on Postgres 16 + `apache/kafka`, Flyway migration, `ddl-auto: validate` | 1 end-to-end test green | `spring-boot-starter-flyway` + `flyway-database-postgresql`; `spring-boot-starter-kafka`; `OutboxWriter` uses `tools.jackson.databind.ObjectMapper` and the unchecked `tools.jackson.core.JacksonException`; Testcontainers 2.x `testcontainers-postgresql` / `testcontainers-kafka` |
| `openapi-generator-maven-plugin` 7.17.0 output (`useSpringBoot3` generates code that compiles and runs) with the full `ci` pom gates (Spotless, Checkstyle, NullAway, SpotBugs, JaCoCo 85/75, PIT 75) | `mvn clean verify` green | `spring-boot-starter-webmvc`; `@WebMvcTest` is `org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest` from `spring-boot-starter-webmvc-test` |

## Not verified on 4.x (do not assume)

RabbitMQ variant (`messaging` `references/rabbitmq.md`), `@RetryableTopic` retry/DLT run against a broker with the 4.x
`@BackOff` variant, ShedLock beyond the relay lock, `EncryptionConverter` on Hibernate 7, the Jackson 3 form of the
`@Mask` serializer (`ValueSerializer`), springdoc, native `@Retryable` / `@ConcurrencyLimit`
(`org.springframework.resilience.annotation` exist in spring-context 7.0.10, but no behaviour was tested, so keep
Resilience4j as the documented choice), Helm/Docker image on a Boot 4 service, the generated `Invoice_` metamodel
(`hibernate-processor`). The JPA/Flyway/Kafka run above used a slim application, not the full rendered service.

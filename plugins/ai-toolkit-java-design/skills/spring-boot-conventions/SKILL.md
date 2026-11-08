---
name: spring-boot-conventions
description: >
  Java / Spring Boot 3 idioms — @ConfigurationProperties over @Value, profiles, conditional beans, @Async with named
  executors, caching, pagination, idempotency, application events. Use whenever a Spring Boot feature is about to be
  used.
tier: must
applies_to: [rest, event, scheduler, monolith]
depends_on: [code-structure]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Spring Boot Conventions Skill
A single source of truth for the Spring Boot idioms the project commits to.
Use this skill as a checklist whenever you reach for a Spring feature; pick
the canonical option below.

## 1. Configuration: `@ConfigurationProperties` over `@Value`

**Default.** Group every related set of properties into a single
`@ConfigurationProperties` record. `@Value` is permitted only for a single
isolated value (e.g. a feature flag).

```java
@ConfigurationProperties(prefix = "foo.dependency")
@Validated                                    // without it the constraints below are never checked
public record FooDependencyProperties(
        @NotBlank String baseUrl,
        @NotBlank String simpleSearchEndpoint,
        @PositiveOrZero int connectTimeoutMs,
        @PositiveOrZero int readTimeoutMs) {}
```

```java
@SpringBootApplication
@ConfigurationPropertiesScan
public class FooApplication { ... }
```

Rules:
- Use a **`record`** so the properties object is immutable.
- Add `@NotBlank` / `@Positive` / `@Min` / `@Max` **and `@Validated` on the record** so misconfiguration fails
  fast at startup — constraints on a `@ConfigurationProperties` class are only checked when it is `@Validated`.
- Add `spring-boot-configuration-processor` as an `optional` dependency (it is **not** on the classpath via the starter): it generates the
  IDE metadata. `META-INF/additional-spring-configuration-metadata.json` is hand-written, only for keys the processor cannot see.
- Match the prefix to the package convention: `<bounded-context>.<feature>`.

## 2. Profiles & YAML Inheritance

Spring Boot's profile mechanism (`spring.profiles.active`) allows for environment-specific configuration. Follow these inheritance rules:

1. **`application.yaml`**: Contains **all** keys with local-friendly defaults.
2. **`application-{profile}.yaml`**: Overrides only what is different for that environment (e.g., `prod`, staging).
3. **Environment Variables**: Use `${VAR_NAME:default}` in the YAML files. This is the preferred way to inject secrets and dynamic infrastructure hostnames (e.g., in Helm charts).

**Reference Profile Strategy**:
- `default`: Local development against a local DB / Docker Compose.
- `test`: Used during `mvn test`. Unit tests need no database; tests that do use Testcontainers — never embedded H2 (`integration-tests`).
- `k8s`: Common baseline for all Kubernetes environments.
- `prod`: Strict production overrides.

**Never** use profiles to toggle business logic; use **Feature Flags** for that. Profiles are for **infrastructure connectivity**.

## 3. Conditional beans (the key SDK lever)

Use `@Conditional*` so the project can opt into / out of optional features
without code changes:

| Annotation | When |
| --- | --- |
| `@ConditionalOnProperty(name = "foo.feature.enabled", havingValue = "true")` | Feature flag |
| `@ConditionalOnMissingBean` | Provide a default that the consumer can override |
| `@ConditionalOnClass(name = "io.micrometer.…")` | Activate only if a library is on the classpath |
| `@ConditionalOnBean(MeterRegistry.class)` | Activate only if a collaborator already exists |

The combination `@Bean + @ConditionalOnMissingBean` is the foundation of the
**lego-brick producer side** (see `sdk-publishing` skill).

## 4. Validation (JSR-380)

```java
@RestController
@RequestMapping("/api/v1/foo")
@Validated
public class FooController {
    @PostMapping
    public ResponseEntity<FooResponse> create(@Valid @RequestBody FooRequest req) { … }

    @GetMapping("/{id}")
    public FooResponse get(@PathVariable @NotBlank String id) { … }
}
```

- `@Valid` on `@RequestBody` triggers nested-bean validation.
- `@Validated` on the controller class enables param-level validation for
  `@PathVariable` / `@RequestParam`.
- `MethodArgumentNotValidException` (and, on Spring 6.1+, `HandlerMethodValidationException`) → `400 ProblemDetail` automatically via
  `ResponseEntityExceptionHandler`. **`ConstraintViolationException`** (parameter constraints under class-level `@Validated`) is *not* handled by it —
  add an explicit `@ExceptionHandler` returning `400` (the `exception-handling` template has one), or it becomes a `500`.
- Use **Jakarta Bean Validation annotations** on the DTO record itself, not
  on the controller signature — except for single `@PathVariable` /
  `@RequestParam` values, which have no DTO and are constrained in the
  signature (the reason for `@Validated` on the controller class).

## 5. OpenAPI documentation

Add `springdoc-openapi-starter-webmvc-ui` (or `-webflux-ui`).

```yaml
springdoc:
  api-docs.path: /v3/api-docs
  swagger-ui.path: /swagger-ui.html
  packagesToScan: {{basePackage}}.controller
```

- One **`@Operation`** and **`@ApiResponses`** per endpoint.
- Group endpoints with **`@Tag`** at the controller level.
- The OpenAPI spec served at `/v3/api-docs` is the **contract** — pin it in
  CI via a snapshot test so changes break the build.

## 6. Pagination contract

For any list endpoint with > a few results, accept `Pageable` and return
`Page<T>`:

```java
@GetMapping
public Page<FooResponse> list(@ParameterObject Pageable pageable) { … }
```

- Default page size: 20, max: 100 (set via `spring.data.web.pageable.*`).
- Response shape is standardised — do not let `PageImpl` be serialized as-is (Spring Data 3.3+ warns). Either:
  - enable `@EnableSpringDataWebSupport(pageSerializationMode = VIA_DTO)` and keep returning `Page<T>`: it is written as
    Spring Data's `PagedModel`, so clients rely on `content` plus a nested `page` object (`size`, `number`, `totalElements`, `totalPages`); or
  - map the `Page<T>` to your own page DTO record and return that, when clients need `content`, `totalElements`, `totalPages`,
    `number`, `size` at the top level.
- For cursor-based pagination (when offset is too expensive), expose a
  `pageToken` query param and an opaque next-token in the body; document
  both in the OpenAPI spec.

## 7. Async work — named `TaskExecutor`

Never inject the framework's default `taskExecutor`. Define your own per
purpose so thread pools are sized and observable:

```java
@Configuration
public class TaskExecutorsConfig {
    @Bean("fooAsyncExecutor")
    public ThreadPoolTaskExecutor fooAsyncExecutor() {
        var ex = new ThreadPoolTaskExecutor();
        ex.setCorePoolSize(4);
        ex.setMaxPoolSize(16);
        ex.setQueueCapacity(100);
        ex.setThreadNamePrefix("foo-async-");
        ex.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        ex.initialize();
        return ex;
    }
}

@Async("fooAsyncExecutor")
public CompletableFuture<Result> doExpensiveWork(...) { … }
```

Enable with `@EnableAsync` on a `@Configuration` class. Apply the
concurrency rules from `code-structure` (`@PreDestroy` cleanup, restore
interrupt flag).

## 7b. Scheduled jobs — `@Scheduled`

Recurring work (cache eviction, throttle reset, retry sweeper, metrics
roll-up) uses `@Scheduled` on a dedicated `*Task` / `*Job` component, never
on a controller or a domain service.

```java
@Slf4j
@Component
@RequiredArgsConstructor
public class ExpiredSessionCleanupTask {

    private final ExpiredSessionStore store;

    @Scheduled(fixedRateString = "${session.cleanup.interval-ms:300000}")
    public void cleanup() {
        try {
            int evicted = store.evictExpired();
            log.info("expired-session-cleanup evicted={}", evicted);
        } catch (Exception e) {
            log.error("expired-session-cleanup failed", e);     // never propagate
        }
    }
}
```

Enabling:

```java
@Configuration
@EnableScheduling
class SchedulingConfig {}
```

— never put `@EnableScheduling` on `@SpringBootApplication`; that couples
the lifecycle of every test slice to the scheduler thread.

Rules:

- **Interval comes from `@ConfigurationProperties`** (or
  `fixedRateString = "${prop:default}"`). Never hard-code milliseconds.
- The task **must complete in `<<` period** under p99 load. If the work is
  unbounded, push it onto a queue and have the task drain N items.
- The task is **idempotent**. If it overlaps itself (slow tick) the second
  run must be a no-op.
- The task **never throws** — always `try/catch`, log and count the failure. (Spring's default error handler logs an uncaught exception and the
  schedule keeps running, so an unhandled failure is easy to miss — it raises no metric or alert on its own.)
- One Micrometer **timer per task** (`scheduled.task.duration{name=…}`)
  and one counter for failures.
- **Cluster safety:** with `replicas > 1`, plain `@Scheduled` runs on
  every pod. Either accept that (idempotent task) or wrap the body with
  [Shedlock](https://github.com/lukas-krecan/ShedLock). For complex job
  graphs use Quartz instead.
- On shutdown, in-flight ticks must drain — cross-ref `graceful-shutdown`.

Forbidden:

- `@Scheduled` on a `@RestController` or any class with HTTP handlers.
- `fixedDelay` / `fixedRate` with a numeric literal (`fixedRate = 60000`).
- Catching `Throwable` without logging.
- Sharing mutable state across tick instances.

## 8. Caching

Use Spring Cache (`@EnableCaching` + `@Cacheable`) only when:
- the underlying call is **pure** (same input ⇒ same output, modulo TTL);
- the **key** can be expressed declaratively (`@Cacheable(key = "#id")`);
- a **cache name** is unique and documented.

Always pick a concrete provider (Caffeine for in-process, Redis for shared)
— never rely on `ConcurrentMapCacheManager` in production.

```java
@Cacheable(cacheNames = "foo-by-id", key = "#id")
public Foo findById(String id) { … }
```

## 9. Idempotency

For state-changing endpoints (`POST` / `PATCH`) that may be retried by
clients:

- Accept an `Idempotency-Key` HTTP header.
- Cache the *response* keyed by `(method, path, idempotencyKey, requestBodyHash)`
  for at least 24 hours.
- Document the contract in OpenAPI (`@Parameter(in = HEADER, ...)`).
- Reject mismatched bodies for the same key with `409 Conflict`.

## 10. Application events

Cross-cutting fan-out inside a microservice (audit log, metrics, cache
invalidation) goes through `ApplicationEventPublisher` rather than direct
calls:

```java
publisher.publishEvent(new FooCreatedEvent(fooId, Instant.now(clock)));   // injected Clock, never Instant.now()

@TransactionalEventListener(phase = AFTER_COMMIT)   // only fires inside a transaction; add fallbackExecution = true or the event is silently dropped
public void onFooCreated(FooCreatedEvent e) { … }
```

Rules:
- Events are **immutable records**.
- Cross-service fan-out goes through Kafka / a message broker, **never**
  Spring events.

## 11. HTTP client

For any new outbound HTTP integration, use **`RestClient`** (Spring 6.1+)
synchronously or **`WebClient`** reactively. Never use `RestTemplate` in new
code.

## 12. Time

Inject `Clock` everywhere code reads "now":

```java
@Bean Clock clock() { return Clock.systemUTC(); }

@Component
public class FooService {
    private final Clock clock;
    @Autowired FooService(Clock clock) { this.clock = clock; }

    Instant now() { return Instant.now(clock); }
}
```

Tests pass `Clock.fixed(...)` so time-dependent logic is deterministic.

## Do / Don't

✅ One `@ConfigurationProperties` per feature; validate at startup.
✅ Conditional beans for everything optional; never `if (env.equals("prod"))`.
✅ Async / cache providers are explicit, named, sized.
✅ Inject `Clock` for time; never call `Instant.now()` statically inside
business code.
❌ Never use `@Value` for a group of related properties.
❌ Never use `RestTemplate` in new code.
❌ Never `@Async` on a method whose return type is `void` — use
`CompletableFuture<Void>` so callers can wait.
❌ Never put values that differ per environment in a profile file; they come from env vars (profiles carry shared infrastructure defaults only).


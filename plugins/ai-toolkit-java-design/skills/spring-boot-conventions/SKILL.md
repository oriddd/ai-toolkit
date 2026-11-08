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
isolated value (e.g. a single timeout read in one place). Feature flags are not
`@Value`s — they go through the `FeatureTogglePort` (`feature-flags`).

```java
@ConfigurationProperties(prefix = ConfigurationConstants.FOO_DEPENDENCY_PREFIX)   // "foo.dependency"
@Validated                                    // without it the constraints below are never checked
public record FooDependencyProperties(
        @NotBlank String baseUrl,
        @NotBlank String simpleSearchEndpoint,
        @NotNull Duration connectTimeout,           // "2s", "500ms" — Boot binds Duration natively
        @NotNull Duration readTimeout) {}
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
- **Keys live in `constant/ConfigurationConstants`** (`code-structure`): one constant per prefix, used by the
  `@ConfigurationProperties(prefix = …)` record and by any `@ConditionalOnProperty` / `@Value` / `${…}` reference, so a
  key is never spelled twice as a string literal.
- Register records with `@ConfigurationPropertiesScan` (above) or `@EnableConfigurationProperties` — a record that
  is neither scanned nor enabled is never bound.

## 2. Profiles & YAML Inheritance

Spring Boot's profile mechanism (`spring.profiles.active`) allows for environment-specific configuration. Follow these inheritance rules:

1. **`application.yaml`**: Contains **all** keys with local-friendly defaults.
2. **`application-{profile}.yaml`**: Overrides only what is different for that **class** of environment (e.g., `k8s`, `prod`) — shared infrastructure defaults, never values that differ between two concrete environments (staging vs prod hostnames, credentials).
3. **Environment Variables**: values that differ per concrete environment come from env vars (set by the Helm chart). Use `${VAR_NAME:default}` for non-secret infrastructure values (hostnames, ports, pool sizes). **Secrets use `${VAR_NAME}` with no default** (or a secret store, see `security-hardening`) — a default such as `${DB_PASSWORD:changeme}` silently ships a known password when the variable is missing.

**Reference Profile Strategy**:
- `default`: Local development against a local DB / Docker Compose.
- `test`: Used during `mvn test`. Unit tests need no database and no containers. Tests that need a real database use Testcontainers — never embedded H2 — and run as integration tests (`*IT`, Failsafe, `mvn verify`), not in `mvn test` (`integration-tests`).
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
| `@ConditionalOnBean(MeterRegistry.class)` | Activate only if a collaborator already exists — **only reliable in an auto-configuration class** (see below) |

The combination `@Bean + @ConditionalOnMissingBean` is the foundation of the
**lego-brick producer side** (see `sdk-publishing` skill).

> **`@ConditionalOnBean` / `@ConditionalOnMissingBean` caveat.** They only see bean definitions registered *before* the
> condition is evaluated. User `@Configuration` classes are processed before auto-configuration, so
> `@ConditionalOnBean(MeterRegistry.class)` in your own `@Configuration` is evaluated before Boot registers the
> `MeterRegistry` and is always false. Use these conditions only in an `@AutoConfiguration` class (ordered with
> `after = …`, as in `sdk-publishing`); in application code inject an `ObjectProvider<MeterRegistry>` and call
> `ifAvailable(…)` instead.

## 4. Validation (JSR-380)

```java
@RestController
@RequestMapping("/api/v1/foo")
public class FooController {          // no class-level @Validated on Spring 6.1+ — see below
    @PostMapping
    public ResponseEntity<FooResponse> create(@Valid @RequestBody FooRequest req) { … }

    @GetMapping("/{id}")
    public FooResponse get(@PathVariable @NotBlank String id) { … }
}
```

- `@Valid` on `@RequestBody` triggers nested-bean validation.
- Param-level validation for `@PathVariable` / `@RequestParam`: on **Spring 6.1+ (Boot 3.2+, so the pinned Boot 3.5)**
  Spring MVC's built-in method validation checks constraints placed directly on controller parameters — no
  class-level `@Validated` needed — and raises `HandlerMethodValidationException`. This is the default choice:
  it is mapped to `400 ProblemDetail` by `ResponseEntityExceptionHandler` like the body errors.
  On older Spring, `@Validated` on the controller class enabled param-level validation through the AOP
  `MethodValidationPostProcessor`; if a controller still carries class-level `@Validated`, that AOP path runs instead.
- `MethodArgumentNotValidException` (and, on Spring 6.1+, `HandlerMethodValidationException`) → `400 ProblemDetail` automatically via
  `ResponseEntityExceptionHandler`. **`ConstraintViolationException`** (parameter constraints under class-level `@Validated`) is *not* handled by it —
  add an explicit `@ExceptionHandler` returning `400` (the `exception-handling` template has one), or it becomes a `500`.
- Use **Jakarta Bean Validation annotations** on the DTO record itself, not
  on the controller signature — except for single `@PathVariable` /
  `@RequestParam` values, which have no DTO and are constrained in the
  signature (validated by Spring 6.1+ built-in method validation, see above).

## 5. OpenAPI documentation

Add `springdoc-openapi-starter-webmvc-ui` (or `-webflux-ui`).

```yaml
springdoc:
  api-docs.path: /v3/api-docs
  swagger-ui.path: /swagger-ui.html
  packagesToScan: com.example.billing.invoice.controller   # your <root package>.controller
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

## Reference map — load only the part you are working on

Sections below keep their numbers but live in `references/` so this file stays small. Read only the file you need.

| Sections | Topic | Load when | File |
| --- | --- | --- | --- |
| §7, §7b, §8 | `@Async` with a named `TaskExecutor` (rejection policy, shutdown draining, interrupts, virtual threads); `@Scheduled` jobs (config-driven interval, never throws, metrics, ShedLock); caching (`CachePort` default, `@Cacheable` shortcut, per-cache TTL, self-invocation) | adding async work, a scheduled job or a cache | [`async-scheduling-and-caching.md`](./references/async-scheduling-and-caching.md) |

## 9. Idempotency

For state-changing endpoints (`POST` / `PATCH`) that may be retried by
clients:

- Accept an `Idempotency-Key` HTTP header.
- Cache the *response* keyed by `(principal / tenant, method, path, idempotencyKey)`
  for at least 24 hours. Store the **request-body hash as part of the value**, not the key — a key that includes the
  body hash can never detect a mismatch. Scoping the key by the authenticated caller (and tenant) stops one user
  replaying, or reading, another user's response by guessing a key.
- Claim the key **atomically** before doing the work (e.g. `INSERT … ON CONFLICT DO NOTHING` / Redis `SET NX` with a
  short lease) with a `PROCESSING` marker; replace it with the stored response when the work completes, and delete
  it if the work fails so the client can retry.
- Document the contract in OpenAPI (`@Parameter(in = HEADER, ...)`).
- Same key, **same** body hash, completed → replay the stored response.
- Reject mismatched bodies for the same key with `422 Unprocessable Entity` (as in `api-design` §2, following the
  IETF Idempotency-Key draft); a duplicate that arrives while the first request is still `PROCESSING` also gets `409 Conflict`
  (with `Retry-After`), never a second execution.

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
- An `AFTER_COMMIT` listener runs after the original transaction has committed: any DB write it makes must run in a
  **new** transaction (`@Transactional(propagation = REQUIRES_NEW)` on the listener or the service it calls), otherwise
  the write is silently not committed.
- Spring events live in memory: if the pod dies between commit and listener, the event is lost. Events that **must
  not be lost** go through the transactional outbox (`messaging`), not an `AFTER_COMMIT` listener.
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
@RequiredArgsConstructor
public class FooService {
    private final Clock clock;

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
`CompletableFuture<Void>` so callers can wait. The caller must `join()` it or attach `whenComplete(…)` /
`exceptionally(…)` that logs and counts the failure — a future nobody observes swallows its exception as silently
as a `void` method.
❌ Never put values that differ per environment in a profile file; they come from env vars (profiles carry shared infrastructure defaults only).


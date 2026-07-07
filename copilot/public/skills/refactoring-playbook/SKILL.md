---
name: refactoring-playbook
description: Step-by-step migrations from common anti-patterns to the canonical patterns shipped by the other public skills — `@Value` → `@ConfigurationProperties` record, `if/else` on type → Strategy + Handler, `RestTemplate` → `RestClient` / `WebClient` + Decorator, anaemic service → DDD Aggregate, hand-rolled retry → Resilience4j, `@MockBean` everywhere → `@TestConfiguration` + boundary fakes. Use during a quality review or before a major version bump.
tier: may
applies_to: [rest, event, scheduler, library, monolith]
depends_on: [quality-review]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Refactoring Playbook Skill (public — meta)

For each anti-pattern, this skill prescribes a **safe, mechanical** migration
to the canonical pattern. Each migration is "green-bar-only" — never break
the build mid-refactor.

## 1. `@Value` fields → `@ConfigurationProperties` record

Symptom: 5+ `@Value("${...}")` fields in the same class.

```diff
- @Value("${foo.base-url}") private String baseUrl;
- @Value("${foo.timeout-ms}") private int timeoutMs;
+ private final FooProperties props;
```

Steps:
1. Create `FooProperties` record (see `spring-boot-conventions` §1).
2. Add `@EnableConfigurationProperties(FooProperties.class)` (or
   `@ConfigurationPropertiesScan`).
3. Replace `@Value` fields with `FooProperties props` injected via
   constructor.
4. Run tests.
5. Delete the old `@Value` lines.

## 2. `if/else` on a type discriminator → Strategy + Handler

Symptom: `if (ctx == USER) … else if (ctx == SERVICE_ACCOUNT) …`.

Steps:
1. Extract the interface `XxxStrategy` with a `supports(...)` method.
2. Move each branch into a `@Component` strategy class.
3. Create a `Handler` (`@Component`) that takes `List<XxxStrategy>` and
   dispatches by `supports`.
4. Replace the original `if/else` with `handler.handle(input)`.
5. Delete the dead `if` after green tests.

See `code-structure` §2 + `permissions` for the canonical shape.

## 3. `RestTemplate` → `RestClient` + Decorator

Symptom: `RestTemplate` calls, retry/cache logic inline, no domain
exception translation.

Steps:
1. Introduce a `FooClient` interface mirroring the methods used.
2. Implement it with `RestClient` (sync) or `WebClient` (reactive); wrap
   non-2xx into a `FooException` at the boundary.
3. Wrap with a `MeteredFooClient` decorator (Micrometer Timer).
4. Add Resilience4j `@CircuitBreaker` + `@Retry` (see `external-client`).
5. Replace callers; the old `RestTemplate` bean becomes a candidate for
   deletion (do it in a separate PR).

## 4. Anaemic service → Aggregate with invariants

Symptom: service with `setX(...)`, `getX()` everywhere; invariants checked
in service methods, not on the data type.

Steps:
1. Identify the consistency boundary → that's the aggregate root.
2. Move invariants from `*Service.create(...)` / `update(...)` onto the
   aggregate (`Foo.create(...)`, `foo.rename(...)`).
3. Make fields private + remove setters.
4. Make collections return immutable copies.
5. Replace primitive ids with Value Objects.
6. Service becomes a thin orchestrator: load aggregate → call domain
   method → save.

See `domain-modeling` §2.

## 5. Hand-rolled retry → Resilience4j

Symptom: a `for (int i = 0; i < 3; i++)` loop in client code.

Steps:
1. Add `resilience4j-spring-boot3`.
2. Configure thresholds in `application.yaml` per dependency.
3. Annotate the client method with `@Retry(name = "foo")` (+
   `@CircuitBreaker` if external).
4. Provide a fallback method that **throws a domain exception** — never
   returns a silent default.
5. Delete the hand-rolled loop.

See `external-client` "Resilience" section.

## 6. `@MockBean` everywhere → `@TestConfiguration` + boundary fakes

Symptom: every component test has its own `@MockBean PermissionsHandler`;
context reloads on every class; slow suite.

Steps:
1. Create `ComponentTestConfiguration` with `@Profile("component-test")` +
   `@Primary` beans (see `component-tests` §1).
2. Make the fake branch on inputs so it can drive forbidden / not-found /
   success from the same instance.
3. Replace `@MockBean` lines in test classes with `@Import(ComponentTestConfiguration.class)`.
4. Add `Mockito.reset(...)` in `@AfterEach` where needed.

## 7. Hibernate auto-DDL → Flyway

Symptom: `spring.jpa.hibernate.ddl-auto=update` in `application.yaml`.

Steps:
1. Set `ddl-auto=validate` in prod, `none` elsewhere.
2. Add `flyway-core`.
3. Capture the current schema with `flyway baseline` → write as
   `V001__baseline.sql`.
4. From now on, every schema change is a new `V00N__*.sql`.
5. Add a Testcontainer-based migration test (see `integration-tests`).

## 8. JSON `Map<String,Object>` request → typed record + `@Valid`

Symptom: controller takes `Map<String,Object>` and casts.

Steps:
1. Define a `FooRequest` record with JSR-380 annotations.
2. Replace the controller param with `@Valid @RequestBody FooRequest`.
3. Generated `MethodArgumentNotValidException` → already mapped to
   `400 ProblemDetail` by your advice.

## 9. Synchronous in-process side-effect → Application event

Symptom: `auditLog.write(...)`, `cacheInvalidator.evict(...)` called
inline in a service.

Steps:
1. Define a domain event record.
2. Replace the inline call with
   `applicationEventPublisher.publishEvent(new FooHappenedEvent(...))`.
3. Move the side-effect into a `@TransactionalEventListener(phase = AFTER_COMMIT)`.

See `spring-boot-conventions` §10.

## 10. Hand-rolled HTTP server in main → Spring Boot

The bridge if you inherited a legacy `main(...)` server: wrap it in a
`@SpringBootApplication`, expose the routes via `@RestController`,
gradually delete the hand-rolled router. Worth its own ADR.

---

## Migration discipline

- One refactor at a time. Mix two and you cannot tell which broke the
  build.
- Tests stay green after every commit. If they can't, write a test first
  that exercises the existing behaviour, then refactor.
- Open a small PR per migration with a link back to the relevant skill —
  reviewers know exactly what to check.
- Add an ADR if the migration changes a published contract.

## Do / Don't

✅ Refactor opportunistically (Boy Scout rule) when touching adjacent code.
✅ Tie every PR title to a playbook entry: "refactor: migrate FooService to
strategy+handler (playbook §2)".
❌ Never do a sweeping rename in the same PR as a behaviour change.
❌ Never refactor without first having a test that pins the current
behaviour.


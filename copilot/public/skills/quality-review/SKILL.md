---
name: quality-review
description: Run a SOLID / clean-code / testability / project-conventions review on a class, package, or pull request. Produces a structured report flagging violations of the project's quality bar (SRP, OCP, ISP, DIP, lego-brick packaging, SDK-style client wrapping, testability anti-patterns like static methods/global state, exception/logging/concurrency conventions, test meaningfulness, positive & negative test coverage) with concrete fix suggestions. Use before opening a PR or when refactoring legacy code into the project standard.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: [unit-tests, static-analysis, testable-code-principles]
ships_templates: false
hitl: false
version: 1.1
last_reviewed: 2026-07-12
---

# this Quality Review Skill

This skill performs a structured, evidence-based review of Java code against
the project conventions. The output is a **report**, not a refactor — the
developer accepts/rejects each finding and applies fixes (optionally via the
other skills).

## When to invoke

- Before opening a PR (run on the diff).
- When onboarding a legacy class to project conventions.
- During design review of a new package.

## Inputs

- A class, a package, or a list of changed files.
- Optionally: the test class(es) for the code under review.

## Review checklist (run **every** item; report PASS / FAIL / N/A + evidence)

### A. SOLID

1. **SRP** — Does the class have one reason to change?
   *Smell:* >300 LOC, mixed responsibilities (HTTP + DTO build + business
   logic), method names spanning unrelated nouns.
   *Fix template:* extract a `*Parser` / `*Builder` / `*Transformer` /
   `*ResponseHandler` companion class — exactly as
   `FooDependencyRequestBuilder` and `BarResponseTransformer`
   were extracted from their clients.

2. **OCP** — To add a new behaviour, do you add a class or modify a switch?
   *Smell:* `if/else` on a type discriminator (`if (ctx == USER) … else if (ctx == SERVICE) …`),
   `switch` on an enum that lists business cases.
   *Fix:* replace with the Strategy + Registry pattern (see
   `code-structure` Pattern A and
   `permission/PermissionsHandler`, `converter/registry/DocumentConverterRegistry`).

3. **LSP** — Do subclasses preserve the contract of their supertype?
   *Smell:* subclass throws on inherited method, narrows accepted input,
   strengthens preconditions.
   *Fix:* prefer composition; or hoist the differing behaviour into a
   dedicated sub-interface (e.g. `FooConverterToHtml extends FooConverter`
   fixes only `getTargetFormat()` — see "lego sub-interface" below).

4. **ISP** — Are interfaces narrow and single-purpose?
   *Smell:* an interface with >3 methods that no single implementation uses
   together.
   *Fix:* split. Reference: `TrivialSpi` has **one** method;
   `PermissionsCheckStrategy` has two and they are inseparable.

5. **DIP** — Does the class depend on abstractions, not concretions?
   *Smell:* field injection (`@Autowired` field), `new ConcreteClient()` in
   business code, static singletons.
   *Fix:* constructor injection only — either
   `@RequiredArgsConstructor(onConstructor = @__(@Autowired))` or an explicit
   `@Autowired` constructor. **One** style per class.

### B. Lego-brick packaging

6. **Package hierarchy** matches `code-structure` §1
   (`controller / operation / service / client / converter / permission / monitor / model / exception / health / constant`).

7. **External dependency wrapping** — every outbound call goes through a
   `client/<dep>/` sub-package with `*Config + *Client + *RequestBuilder +
   *ResponseHandler (+ transformer)`. See `external-client`. Detect
   leaks: any `WebClient` / `RestTemplate` / gRPC stub injected outside
   `client/`.

8. **Lego sub-interface trick** — when many implementations of a strategy
   share a common axis (target format, supported context, …), the axis is
   factored into a sub-interface with a `default` method:
   ```java
   public interface FooConverterToHtml extends FooConverter {
       @Override default String getTargetFormat() { return HTML.getFileExtension(); }
   }
   ```
   so concrete classes only declare the dimension that actually varies. Flag
   if N concrete classes repeat the same method literally.

### C. Cross-cutting conventions

9a. **Nullable fetch → filtered stream.** Any collaborator whose
    contract documents `null` on error (graceful degradation) must be
    filtered with `.filter(Objects::nonNull)` at the call-site before
    downstream `map` / `flatMap`. Flag streams that call such methods
    without a null filter.
    *Fix:* add the filter; or promote the return type to `Optional<T>`
    and force the caller to unwrap.

9b. **No `@EnableXxx` on `@SpringBootApplication`.**
    `@EnableScheduling`, `@EnableAsync`, `@EnableCaching`,
    `@EnableConfigurationPropertiesScan` must live on dedicated
    `@Configuration` classes (`SchedulingConfig`, `AsyncConfig`, …) so
    test slices can opt out. See `spring-boot-conventions` §7b.

9c. **One properties bean per dependency.** No infrastructure property
    key (`*.endpoint`, `*.namespace`, `*.topic`, `*.timeout-ms`) may be
    read via `@Value` in more than one class. Flag any such duplicate;
    the fix is a shared `@ConfigurationProperties` record.

9d. **Layer duplication.** Two classes in different packages
    implementing the same capability (list-by-status query, event-history
    reduction) is a smell — one must be the canonical implementation, the
    other deleted. Flag any pair of classes that share ≥ 80 % of a
    switch statement or query-building expression across packages.

9e. **Scheduler purity.** A `@Scheduled` bean may only depend on
    `service/`, `repository/`, `analyzer/`, and its own logger. Flag any
    scheduler that injects a `*Client`, `WebClient`, SDK stub, or reads
    infrastructure `@Value` fields directly.

9. **Exceptions** — Throw-site uses a domain exception (`*Exception`,
   `*BadRequestException`, `*ForbiddenException`, `*NotFoundException`) with
   a `MessageFormat`-formatted message from `ExceptionMessages`. The HTTP
   mapping lives only in the `@RestControllerAdvice`. (See
   `exception-handling`.) Flag any `throw new RuntimeException("…")`
   in business code or inline error string.

10. **Logging** — `@Slf4j` / `@Log4j2`; no `System.out`; no logging of secrets
    or full URLs with credentials; `log.debug` for happy-path detail,
    `log.warn` for recoverable, `log.error` for unexpected with exception as
    last arg (not concatenated).

11. **Constants** — Utility classes are `final` with
    `@NoArgsConstructor(access = PRIVATE)`; magic strings live in a `*Constants`
    class; config keys live in `ConfigurationConstants` as
    `${prop.name}` / SpEL `#{'${prop.list}'.split(',')}`. Flag inline
    `@Value("${…}")` literals that occur more than once.

12. **Concurrency** — Any `ExecutorService` field has:
    - a `@PreDestroy` that calls `shutdown()` → `awaitTermination(…)` →
      `shutdownNow()`;
    - `InterruptedException` handlers restore the flag with
      `Thread.currentThread().interrupt()`.
    `CompletableFuture` chains unwrap the cause when rethrowing (see
    `HeavyStartupOrchestrator.awaitLicenseSettingTasksCompletion`).
    Flag `Thread.sleep` outside of tests, raw `Thread.start()`,
    unmanaged thread pools.

13. **Reactive boundary** — `Mono`/`Flux` are confined to `client/`; the rest
    of the code is synchronous. If a `.block()` appears outside `client/`,
    flag it.

14. **Configuration** — every `@Value`/`@ConfigurationProperties` key has a
    matching `${ENV:default}` entry in `application.yaml`, a Helm env var,
    and (for downstream URLs) a `HealthIndicator`.

### D. Test quality

15. **Coverage shape** — every public method has at minimum:
    happy + every declared exception + every `if/switch` branch + boundary
    (`null`/empty). See `unit-tests`.

16. **Meaningful assertions** — flag tests whose only assertion is
    `assertNotNull(result)` on a method that cannot return `null`; flag tests
    that never `verify` interactions on a class whose contract is its
    side-effects.

17. **Right boundary** — unit tests mock direct collaborators only.
    Component tests mock at the boundary (`*Client`, `PermissionsHandler`,
    blob-store / file-store clients), not the controller/service/operation. Flag `@MockBean`
    on the class under test or on a value object.

18. **Determinism** — no `Thread.sleep`, no time-dependent assertions
    without a `Clock` abstraction, no random data without a seed.

19. **Static / context mocking** — `MockedStatic` is opened in a
    `try-with-resources` inside the test method, never as a class field.
    `clearInvocations` resets shared mocks in `@AfterEach`.

20. **Opt-out test configs** — heavy `@PostConstruct` work
    (license loading, cache priming, big thread pools) has a paired
    `@TestConfiguration` that replaces it with a no-op for component tests
    (see `NoHeavyStartupTestConfig`).

21. **Positive & negative paths** — for every public method, verify tests
    exist for both the happy path (valid inputs) and negative cases (null,
    invalid, exception scenarios). Flag methods with only happy-path tests.
    See `unit-tests` §"Test Every LEGO Brick".

22. **Test naming convention** — test methods follow
    `methodName_condition_expectedResult()` or `when<Condition>_<Then>()`
    naming. Flag vague names like `test1()`, `testMethod()`, `happyPath()`.

### E. Testability Anti-Patterns (see `testable-code-principles`)

23. **Static methods with business logic** — flag any `static` method outside
    of `*Constants`, `*Utils` (pure functions), or test helpers that
    contains business logic. Business logic must be injectable.
    *Smell:* `UserValidator.isValid(user)` instead of `@Component UserValidator`
    with instance method.
    *Fix:* convert to `@Component` with instance method, inject where needed.

24. **Global state / Singletons** — flag static mutable fields, singleton
    pattern implementation, or `getInstance()` methods in business code.
    *Smell:* `private static final Map<String, Config> CACHE = new HashMap<>();`
    or `private static ConfigManager instance;`.
    *Fix:* convert to Spring bean with instance state; inject via constructor.

25. **Hidden dependencies** — flag direct access to `System.getProperty()`,
    `System.getenv()`, `Locale.getDefault()`, `TimeZone.getDefault()` in
    business code (outside of `*Config` classes).
    *Smell:* `String mode = System.getProperty("processing.mode");`.
    *Fix:* inject via `@ConfigurationProperties` or constructor parameter.

26. **Time-dependent logic without Clock** — flag `LocalDate.now()`,
    `Instant.now()`, `System.currentTimeMillis()` without injected `Clock`.
    *Smell:* `if (LocalDate.now().getDayOfWeek() == MONDAY)`.
    *Fix:* inject `Clock`; use `LocalDate.now(clock)` for testability.

27. **Direct file/network I/O in business logic** — flag `new File(...)`,
    `Files.readAllBytes(...)`, `URL.openStream()`, raw JDBC/HTTP in
    `service/` or `operation/`. I/O must be abstracted behind a repository
    or client.
    *Smell:* `byte[] data = Files.readAllBytes(Paths.get("config.json"));`
    in a service method.
    *Fix:* extract `ConfigRepository` or inject `ResourceLoader`.

28. **Hidden side effects** — flag methods whose name suggests a query
    (`get*`, `find*`, `is*`, `has*`, `calculate*`) but contains write
    operations (logging excluded), cache updates, metrics increments, or
    state mutations.
    *Smell:* `public Document findById(String id) { cache.put(id, result); ... }`.
    *Fix:* separate query from command; make side effects explicit in method name.

29. **Constructor doing work** — flag constructors (or `@PostConstruct`)
    that perform I/O, call external services, or heavy computation. Tests
    cannot control timing or mock the work.
    *Smell:* `public FooService() { this.config = loadConfigFromDisk(); }`.
    *Fix:* inject pre-loaded dependencies; defer work to explicit `init()` or
    lazy-load on first use with a supplier.

30. **Unclear inputs/outputs** — flag methods with >4 parameters, methods
    that modify input parameters (mutate collections/arrays passed in),
    or methods returning `void` whose contract relies entirely on side effects
    without a clear naming convention (`save*`, `send*`, `record*`).
    *Smell:* `void process(List<Item> items)` that modifies `items` in place.
    *Fix:* return new collection; or rename to `processInPlace(...)` to make
    mutation explicit.

### F. Quantitative thresholds

For each finding below, cite the value in the report and apply the listed
threshold. These are deliberately strict; treat each violation as a `WARN`
that triggers a refactor conversation (not an automatic `FAIL`, since a
junit-named edge case may justify breaking one).

| Metric | Threshold | Tool |
| --- | --- | --- |
| 21. Cyclomatic complexity per method | **≤ 10** | SpotBugs / PMD |
| 22. Method length (effective LOC, ignoring blank/`}`) | **≤ 30** | manual / Checkstyle |
| 23. Class length | **≤ 300** | Checkstyle |
| 24. Number of method parameters | **≤ 4** (use a record / parameter object beyond) | Checkstyle |
| 25. Number of fields | **≤ 7** (sign of class doing too much) | manual |
| 26. NCSS (non-commenting source statements) per file | **≤ 500** | PMD |
| 27. Class fan-out (number of other types referenced) | **≤ 25** | ArchUnit slice metric |
| 28. Cognitive complexity per method | **≤ 15** | SonarQube |
| 29. Public API surface of a `client/<dep>/` sub-package | **≤ 1 facade type** that callers depend on (others may be public if returned from the facade) | manual |
| 30. Magic literals in business code | **0** — every literal lives in a `*Constants` class or `*Properties` record | grep |
| 31. Line coverage by Jacoco | **≥ 85 % line, ≥ 75 % branch** (per class) | Jacoco |
| 32. Mutation score by PIT | **≥ 75 %** (per package) | PIT |
| 33. Architecture rules in `ArchitectureTest` | **PASS** | ArchUnit |

Surface every violation as:

```
[F21 CYC]  WARN  FooService#computeBucket  complexity 13  (limit 10)
                    Suggested fix: extract decision table into a Map<X, Strategy>.
```



For each item, emit a row:

```
[A1 SRP]   PASS  — class fits one responsibility, 84 LOC.
[B7 SDK ]  FAIL  — `WebClient` injected directly into FooService at line 42.
                    Suggested fix: extract `FooClient` + `FooClientConfig`
                    via the external-client skill.
[D16 TST]  WARN  — `FooServiceTest#happyPath` asserts only `assertNotNull`;
                    add interaction verification on `fooRepository.save(...)`.
```

End with a summary:

- `# total`, `# pass`, `# fail`, `# warn`.
- Top 3 highest-impact fixes.
- Suggested follow-up skills to run (`external-client`,
  `exception-handling`, `unit-tests`, …).

## Do / Don't

✅ Cite **line numbers / class names** as evidence for every finding.
✅ Reference the canonical pattern by skill name so the developer knows where
to look for the template.
✅ When unsure, mark `WARN` not `FAIL`; ambiguity is the reviewer's problem.
❌ Never edit code in this skill — produce a report; the developer applies
fixes via the dedicated skill.
❌ Never report on issues that the parent BOM, ResponseEntityExceptionHandler, or
the Spring Boot starters already solve.


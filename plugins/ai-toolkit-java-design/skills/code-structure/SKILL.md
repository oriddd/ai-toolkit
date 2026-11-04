---
name: code-structure
description: Apply the canonical Java/Spring Boot package hierarchy and design patterns (Strategy + Registry, OncePerRequestFilter for metrics, Recorder pattern, Operation/Service/Controller layering) when creating or refactoring a microservice. Every class is a LEGO brick — small, focused, independently testable; names document the code. Use when creating or editing ANY Java class, package, controller, service or operation in a Spring Boot service — load it before writing code. For validators also apply `input-validation`, and for runtime-selected behaviour also `strategy-registry-pattern`.
tier: must
applies_to: [rest, event, scheduler, monolith]
depends_on: [testable-code-principles]
ships_templates: true
hitl: false
version: 1.1
last_reviewed: 2026-07-12
---

# this Code Structure Skill

Use this skill any time you create a new Java microservice, add a new
feature, or onboard a legacy service. It defines the **package hierarchy** and
the three reference **design patterns** every service must follow.

## 1. Canonical package hierarchy

Root package: `com.example.<domain>.<subdomain>`
(e.g. `com.example.foo`).

```
com.example.<domain>.<subdomain>/
├── <ServiceName>Application.java     # @SpringBootApplication entry-point
├── client/        # outbound HTTP / gRPC clients to other services
├── constant/      # shared compile-time constants
├── controller/    # @RestController REST entry-points (thin, no business logic)
├── renderer/      # domain "renderer strategies" (format export / rendering)
├── exception/     # custom exceptions + exception/constants/ExceptionMessages
├── health/        # Spring Boot HealthIndicator implementations
├── model/         # DTOs (request/response) and internal domain models
├── monitor/       # metrics filter, recorders, parsers (see Pattern B)
├── operation/     # use-case orchestrators (one class per public use case)
├── permission/    # authorization strategies + handler (see Pattern A)
├── repository/    # data-access wrappers around a client/adapter (thin, per fetch shape)
├── analyzer/      # pure-function business logic (status/totals analysis)
├── scheduler/     # @Scheduled tasks — orchestrate only (see rule below)
└── service/       # business logic / IO – called by operations
```

> `repository/`, `analyzer/`, and `scheduler/` are **only present when needed**
> — do not scaffold empty packages. They exist to give background jobs,
> data-access shapes, and pure analysis logic a home *outside* of `service/`
> when a single service class would otherwise mix concerns.

### Layering rules

```
controller ──► operation ──► service ──► repository ──► client
                 │             │              │
                 └──► permission, renderer, monitor (cross-cutting)
                                                │
                                     analyzer (pure functions)
                                                │
                 scheduler ──► service / repository / analyzer  (never client directly)
```

## 1b. The LEGO Bricks Principle (Foundational)

> **Core Philosophy:** Every class and method you write is a LEGO brick that
> snaps together with others. Each brick must be **small**, **focused**, and
> **self-explanatory**.

This principle is foundational to the entire code structure and directly
supports both **SOLID principles** and **testability**. See
[`testable-code-principles`](../testable-code-principles/SKILL.md) for the
complete rationale.

### What makes a good LEGO brick?

**✅ Small and focused:**
- Class: ≤ 200 LOC (preferably ≤ 100)
- Method: ≤ 30 LOC, cyclomatic complexity ≤ 10
- One clear responsibility per class/method

**✅ Self-explanatory names:**
- Class and method names describe **exactly** what the component does
- **No comments needed** to understand the purpose
- Examples: `InvoiceValidator`, `InvoicePdfRenderer`,
  `UserPermissionsCheckStrategy`

**✅ Easy to replace or rearrange:**
- Depends on interfaces, not concrete implementations
- Can be swapped via configuration without changing business logic
- New behavior = new brick, not modification of existing brick (OCP)

**✅ Independently testable:**
- Clear inputs and outputs
- No hidden dependencies (static methods, global state, file I/O)
- Each brick has its own focused test class

### Recognizing when to split a brick

**Smell:** A class needs internal section comments like:
```java
public class InvoiceService {
    // --- validation ---
    private void validate(...) { ... }
    
    // --- transformation ---
    private byte[] transform(...) { ... }
    
    // --- persistence ---
    private void save(...) { ... }
}
```

**Fix:** Each comment reveals a missing brick:
```java
@Component public class InvoiceValidator { ... }      // validation brick
@Component public class InvoiceTransformer { ... }    // transformation brick
@Component public class InvoiceRepository { ... }     // persistence brick

@Component
@RequiredArgsConstructor
public class InvoiceService {
    private final InvoiceValidator validator;
    private final InvoiceTransformer transformer;
    private final InvoiceRepository repository;
    
    public Invoice process(Invoice invoice) {
        validator.validate(invoice);
        byte[] transformed = transformer.transform(invoice.getContent());
        return repository.save(invoice.withContent(transformed));
    }
}
```

Now each brick:
- Has a **single, testable responsibility**
- Can be **replaced** independently (e.g., swap `InvoiceValidator` for
  `StrictInvoiceValidator`)
- Has a **self-explanatory name** — no comments needed
- Is **small** (each class ≤ 50 LOC instead of one 150 LOC class)

### LEGO bricks → SOLID mapping

| LEGO Principle | SOLID Principle | Benefit |
|----------------|-----------------|---------|
| **Small, focused** | Single Responsibility | One test suite per brick, clear failure isolation |
| **Easy to replace** | Open/Closed, Liskov Substitution | Add/swap bricks without breaking existing code or tests |
| **Interface-based** | Dependency Inversion, Interface Segregation | Mock bricks easily in tests; clear contracts |
| **Self-explanatory** | Single Responsibility | Code reads like documentation; minimal comments |

See [`testable-code-principles`](../testable-code-principles/SKILL.md) for
detailed examples of testable vs. non-testable code.

## 1c. Layer Responsibilities

Each layer in the hierarchy has a specific, focused responsibility:

- **Controllers** only translate HTTP ⇄ DTO and delegate to **one** `Operation`.
- **Operations** orchestrate a single use case: permission check → service calls →
  response assembly. No HTTP types here.
- **Services** are stateless beans encapsulating one domain capability.
- **Clients** wrap an external system (HTTP/gRPC). They never throw raw
  framework exceptions – translate to a domain `*Exception` from the
  `exception/` package.
- **Repositories** provide **one method per fetch shape** on top of a client
  (`fetchById`, `fetchByStatus`, `fetchOrderStatus`). They own query-building and
  transport-error handling; they do **not** transform DTOs or apply business
  rules. Split into multiple small classes (`*OrderListFetcher`, `*OrderDetailsFetcher`,
  `*OrderStatusFetcher`) rather than a fat repository.
- **Analyzers** are stateless, side-effect-free functions over domain data
  (`OrderTotalCalculator`, `DiscountEvaluator`). No I/O, no Spring
  dependencies beyond `@Component`. Trivially unit-testable.
- **Schedulers** (`@Scheduled` beans) are **orchestrators only** — they call
  `service/`, `repository/`, and `analyzer/`. A scheduler that queries a
  client directly, builds its own query strings, or re-implements analysis
  logic is a duplication smell → move the logic into `repository/` or
  `analyzer/` and inject it.
- **Models** are immutable where possible (records / `@Value`).
- Cross-cutting concerns (`permission`, `monitor`, `renderer`, `analyzer`)
  live in their own packages and are wired via Spring DI.

### Naming

- One public class per file.
- Suffixes are meaningful: `*Controller`, `*Operation`, `*Service`, `*Client`,
  `*Strategy`, `*Handler`, `*Registry`, `*Recorder`, `*Parser`, `*Filter`,
  `*Config`, `*Exception`, `*Fetcher`, `*Builder`, `*Converter`,
  `*Calculator`, `*Analyzer`, `*Scheduler`, `*Task`.
- **Lego-brick sizing.** Prefer many small, named classes (≤ ~100 lines,
  single responsibility) over one long orchestrator. If a class needs a
  section comment like `// --- totals calculation ---` inside it, that
  section is a missing `*Calculator` / `*Fetcher` / `*Builder`.
- Test classes mirror the package of the class under test under `src/test/java`.

## Reference map — load only the part you are working on

Sections below keep their numbers but live in `references/` so this file stays small. Read only the file you need; do not load them all.

| Sections | Topic | Load when | File |
| --- | --- | --- | --- |
| §2, §3, §4, §4k | Strategy + Handler, Metrics Filter + Recorder Registry, Operation / Service split, Monolith to Module | applying one of the named patterns | [`patterns.md`](./references/patterns.md) |
| §4f–§4j | composition, immutability, visibility, architecture-as-code, pattern catalogue | reviewing design rules or writing ArchUnit tests | [`design-rules-and-archunit.md`](./references/design-rules-and-archunit.md) |

## 5. Cross-cutting conventions

- **Logging:** `@Slf4j` (or `@Log4j2`) – never `System.out`. Use
  `log.debug` for happy-path detail, `log.warn` for recoverable, `log.error`
  for unexpected with the exception as the **last** argument (not
  concatenated). Never log secrets or URLs with credentials.
- **Lombok:** prefer `@RequiredArgsConstructor(onConstructor = @__(@Autowired))`
  for DI; avoid field injection. Pick one style per class.
- **Configuration:** All env-driven config is read from `application.yaml`
  with `${ENV_VAR:default}` placeholders matching the Helm chart env names.
  Keys are centralised in `ConfigurationConstants` (see §4d).
- **Exceptions:** Define a base `<Domain>Exception` and subclasses
  (`*BadRequestException`, `*ForbiddenException`, `*NotFoundException`).
  Static messages live in `exception/constants/ExceptionMessages` and are
  formatted with `MessageFormat`. HTTP mapping happens in a single
  `@RestControllerAdvice` extending `ResponseEntityExceptionHandler` that returns
  `ProblemDetail`. See the **`exception-handling`** skill.
- **Tests:** Test packages mirror `main/`; component tests live in
  `component/`, shared fixtures in `testconfig/` and `testdata/`. Heavy
  `@PostConstruct` work has a paired opt-out `@TestConfiguration` (e.g.
  `NoHeavyStartupTestConfig`).

## 6. Bootstrapping checklist

When applying this skill to a new module:

- [ ] Create the empty package skeleton listed in §1.
- [ ] Create `<ServiceName>Application.java` with `@SpringBootApplication`,
      `@ComponentScan`, `@PropertySource("classpath:application.yaml")`.
      **Never** put `@EnableScheduling` / `@EnableAsync` / `@EnableCaching`
      here — each goes on its own dedicated `@Configuration` class
      (`SchedulingConfig`, `AsyncConfig`, `CachingConfig`) so test slices
      can opt out. See `spring-boot-conventions` §7b.
- [ ] Add `application.yaml` with `server.port`, `server.servlet.context-path`,
      actuator exposure (`prometheus,health,info,httptrace`), and
      `management.endpoint.health.probes.enabled: true`.
- [ ] Add `logback-spring.xml` aligned with `spring-boot-starter-logging`.
- [ ] Create `exception/constants/ExceptionMessages.java`.
- [ ] If the service needs auth → add a `permission/` strategy + handler.
- [ ] If the service has measurable use cases → add a `monitor/` filter + recorder.

## 7. Templates

- [`Application.java.tmpl`](./templates/Application.java.tmpl) — `@SpringBootApplication` entry-point.
- [`ArchitectureTest.java.tmpl`](./templates/ArchitectureTest.java.tmpl) — ArchUnit structural enforcement.
- [`application.yaml.tmpl`](./templates/application.yaml.tmpl) — Baseline Spring configuration.
- [`package-skeleton/`](./templates/package-skeleton/) — Folder structure with `.gitkeep` files.

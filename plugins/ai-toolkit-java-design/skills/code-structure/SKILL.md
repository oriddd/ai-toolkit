---
name: code-structure
description: >
  Java / Spring Boot package hierarchy and layering — controller/operation/service, filter + recorder; every class a
  small, testable LEGO brick. Runtime-selected behaviour: `strategy-registry-pattern`. Use before creating or editing
  ANY Java class, package, controller, service or operation.
tier: must
applies_to: [rest, event, scheduler, monolith]
depends_on: [testable-code-principles]
ships_templates: true
hitl: false
version: 1.1
last_reviewed: 2026-07-12
---

# Code Structure

Use this skill any time you create a new Java microservice, add a new
feature, or onboard a legacy service. It defines the **package hierarchy** and
the three reference **design patterns** every service must follow.

## 1. Canonical package hierarchy

Root package: `com.example.<domain>.<subdomain>`
(e.g. `com.example.billing.invoice`).

```
com.example.<domain>.<subdomain>/
├── <ServiceName>Application.java     # @SpringBootApplication entry-point
├── client/        # outbound HTTP / gRPC clients to other services (client/<dep>/, see external-client)
├── config/        # @Configuration classes + @ConfigurationProperties records (config/<capability>/ for pluggable wiring)
├── constant/      # shared compile-time constants (incl. ConfigurationConstants)
├── controller/    # @RestController REST entry-points (thin, no business logic)
├── renderer/      # domain "renderer strategies" (format export / rendering)
├── exception/     # custom exceptions + exception/constants/ExceptionMessages + exception/handler/GlobalExceptionHandler
├── health/        # health/indicator/ HealthIndicator implementations + health/config/ (see health-indicator)
├── mapper/        # MapStruct mappers AND/OR response-mapper strategies (see Pattern A)
├── model/         # DTOs (request/response) and internal domain models
├── monitor/       # metrics filter, recorder/, parser/ (see Pattern B, request-metrics)
├── operation/     # use-case orchestrators (one class per orchestrated use case)
├── permission/    # authorization strategies + handler (see Pattern A)
├── repository/    # data access, one method per fetch shape (see "repository/" note below)
├── analyzer/      # pure-function business logic (status/totals analysis)
├── scheduler/     # @Scheduled tasks — orchestrate only (see rule below)
├── service/       # business logic / IO – called by controllers or operations
│
│   # Feature packages — created only when the service uses that skill
├── spi/           # project-owned port interfaces: spi/<capability>/ (pluggable-architecture)
├── adapter/       # vendor adapters: adapter/<capability>/<vendor>/ (pluggable-architecture)
├── validation/    # annotation/, validator/, rule/, config/ValidationConfig (input-validation)
├── layout/        # response layout strategies + handler (response-layout)
├── entity/        # JPA @Entity types (persistence)
├── domain/        # aggregates, value objects, domain services (domain-modeling)
├── acl/           # anti-corruption-layer translators to other contexts (domain-modeling)
├── event/         # immutable event records — the contract (messaging, domain-modeling)
└── messaging/     # producer/, consumer/, outbox/ (messaging)
```

> Only `controller/`, `service/`, `model/`, `exception/` and `config/` exist in
> every REST service. Every other package — including `repository/`,
> `analyzer/`, `scheduler/` and the feature packages — is **only present when
> needed**: do not scaffold empty packages. `repository/`, `analyzer/` and
> `scheduler/` exist to give background jobs, data-access shapes, and pure
> analysis logic a home *outside* of `service/` when a single service class
> would otherwise mix concerns.
>
> **`repository/` has one meaning: the data-access layer, one method per fetch
> shape.** With a database it holds Spring Data interfaces (+ Specifications,
> see `persistence`); with a remote source it holds thin `*Fetcher` classes on
> top of a `client/` (see §1c). Business code reaches data only through it.
>
> Event-driven and scheduler services rename the entry/orchestrator packages
> (`consumer/`, `handler/`, `job/`, `producer/` — see `project-types`); the
> same layering and ArchUnit rules apply to them.

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

The controller skips `operation/` and calls exactly one `*Service` when the use
case orchestrates nothing (guild rule 3, see §1c).

## 1b. The LEGO Bricks Principle (Foundational)

> **Core Philosophy:** Every class and method you write is a LEGO brick that
> snaps together with others. Each brick must be **small**, **focused**, and
> **self-explanatory**.

This principle is foundational to the entire code structure and directly
supports both **SOLID principles** and **testability**. See
`testable-code-principles` for the
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

See `testable-code-principles` for
detailed examples of testable vs. non-testable code.

## 1c. Layer Responsibilities

Each layer in the hierarchy has a specific, focused responsibility:

- **Controllers** only translate HTTP ⇄ DTO and delegate to **exactly one**
  entry bean: an `Operation` when the use case orchestrates (permission check,
  several services, response assembly), otherwise a single `*Service` call
  (guild rule 3; see `pattern-selection` for the scale decision).
- **Operations** orchestrate a single use case: permission check → service calls →
  response assembly. No HTTP types here.
- **Services** are stateless beans encapsulating one domain capability.
- **Clients** wrap an external system (HTTP/gRPC). They never throw raw
  framework exceptions – translate to a domain `*Exception` from the
  `exception/` package.
- **Repositories** provide **one method per fetch shape** on top of a client
  (`fetchById`, `fetchByStatus`, `fetchOrderStatus`) — Spring Data interfaces
  for a database, `*Fetcher` classes over a client otherwise. They own query-building and
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
- **Models** are immutable where possible (records, or `@lombok.Value` — never Spring's `@Value`).
- Cross-cutting concerns (`permission`, `monitor`, `renderer`, `analyzer`)
  live in their own packages and are wired via Spring DI.

### Naming

- One public class per file.
- Suffixes are meaningful: `*Controller`, `*Operation`, `*Service`, `*Client`,
  `*Strategy`, `*Handler`, `*Registry`, `*Recorder`, `*Parser`, `*Filter`,
  `*Config`, `*Properties`, `*Exception`, `*Fetcher`, `*Builder`, `*Converter`,
  `*Calculator`, `*Analyzer`, `*Scheduler`, `*Task`, `*Port`, `*Adapter`,
  `*Validator`, `*Rule`, `*Mapper`, `*Renderer`, `*Resolver`.
- **Lego-brick sizing.** Prefer many small, named classes (≤ 200 LOC, aim for
  ≤ 100 — same limit as §1b; single responsibility) over one long orchestrator. If a class needs a
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

- **Logging:** `@Slf4j` – never `System.out`. Use
  `log.debug` for happy-path detail, `log.warn` for recoverable, `log.error`
  for unexpected with the exception as the **last** argument (not
  concatenated). Never log secrets or URLs with credentials.
- **Lombok:** prefer plain `@RequiredArgsConstructor` for DI (a single
  constructor needs no `@Autowired`); avoid field injection. Pick one style per class.
- **Configuration:** All env-driven config is read from `application.yaml`
  into `@ConfigurationProperties` records (see `spring-boot-conventions` §1)
  with `${ENV_VAR:default}` placeholders (secrets: `${ENV_VAR}`, no default) matching the Helm chart env names.
  Keys are centralised in `constant/ConfigurationConstants`.
- **Exceptions:** Define an unchecked base `<Domain>Exception extends RuntimeException` and subclasses
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

- [ ] Create the packages from §1 that this module populates now (never empty
      ones); `templates/package-skeleton/` lists the usual core set.
- [ ] Create `<ServiceName>Application.java` with `@SpringBootApplication` + `@ConfigurationPropertiesScan` only — Boot already scans the package (with the exclude filters
      test slices need) and loads `application.yaml`; a bare `@ComponentScan` would drop those filters and `@PropertySource` cannot read YAML.
      `@ConfigurationPropertiesScan` registers the `@ConfigurationProperties` records (without it they are never bound and startup fails).
      **Never** put `@EnableScheduling` / `@EnableAsync` / `@EnableCaching`
      here — each goes on its own dedicated `@Configuration` class
      (`SchedulingConfig`, `AsyncConfig`, `CachingConfig`) so test slices
      can opt out. See `spring-boot-conventions` §7b.
- [ ] Add `application.yaml` with `spring.application.name`, `server.port`, `server.servlet.context-path`,
      graceful shutdown (`server.shutdown: graceful`, `spring.lifecycle.timeout-per-shutdown-phase`, see `graceful-shutdown`),
      actuator exposure (`prometheus,health,info`), and
      `management.endpoint.health.probes.enabled: true`.
- [ ] Add `logback-spring.xml` aligned with `spring-boot-starter-logging`.
- [ ] Create `exception/constants/ExceptionMessages.java`.
- [ ] If the service needs auth → add a `permission/` strategy + handler.
- [ ] If the service has measurable use cases → add a `monitor/` filter + recorder.

## 7. Templates

- [`Application.java.tmpl`](./templates/Application.java.tmpl) — `@SpringBootApplication` + `@ConfigurationPropertiesScan` entry-point.
- [`ArchitectureTest.java.tmpl`](./templates/ArchitectureTest.java.tmpl) — ArchUnit structural enforcement.
- [`application.yaml.tmpl`](./templates/application.yaml.tmpl) — Baseline Spring configuration.
- [`package-skeleton/`](./templates/package-skeleton/) — Core folder structure with `.gitkeep` files; copy only the folders you populate.

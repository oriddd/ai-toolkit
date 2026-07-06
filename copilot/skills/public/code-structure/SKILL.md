---
name: code-structure
description: Apply the canonical Java/Spring Boot package hierarchy and design patterns (Strategy + Registry, OncePerRequestFilter for metrics, Recorder pattern, Operation/Service/Controller layering) when creating or refactoring a microservice.
tier: must
applies_to: [rest, event, scheduler, monolith]
depends_on: []
ships_templates: true
hitl: false
version: 1.0
last_reviewed: 2026-06-28
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
├── converter/     # MapStruct mappers AND/OR domain "converter strategies"
├── exception/     # custom exceptions + exception/constants/ExceptionMessages
├── health/        # Spring Boot HealthIndicator implementations
├── model/         # DTOs (request/response) and internal domain models
├── monitor/       # metrics filter, recorders, parsers (see Pattern B)
├── operation/     # use-case orchestrators (one class per public use case)
├── permission/    # authorization strategies + handler (see Pattern A)
└── service/       # business logic / IO – called by operations
```

### Layering rules

```
controller ──► operation ──► service ──► client
                 │             │
                 └──► permission, converter, monitor (cross-cutting)
```

- **Controllers** only translate HTTP ⇄ DTO and delegate to **one** `Operation`.
- **Operations** orchestrate a single use case: permission check → service calls →
  response assembly. No HTTP types here.
- **Services** are stateless beans encapsulating one domain capability.
- **Clients** wrap an external system (HTTP/gRPC). They never throw raw
  framework exceptions – translate to a domain `*Exception` from the
  `exception/` package.
- **Models** are immutable where possible (records / `@Value`).
- Cross-cutting concerns (`permission`, `monitor`, `converter`) live in their
  own packages and are wired via Spring DI.

### Naming

- One public class per file.
- Suffixes are meaningful: `*Controller`, `*Operation`, `*Service`, `*Client`,
  `*Strategy`, `*Handler`, `*Registry`, `*Recorder`, `*Parser`, `*Filter`,
  `*Config`, `*Exception`.
- Test classes mirror the package of the class under test under `src/test/java`.

## 2. Pattern A — Strategy + Handler (used in `permission/` and `converter/`)

When the same operation has **multiple interchangeable implementations** chosen
at runtime, use this trio:

1. **`<X>Strategy`** – interface with a `supports(...)` / `canHandle(...)` method
   plus the business method.
2. Concrete `@Component` strategies implementing the interface.
3. **`<X>Handler`** (or `<X>Registry`) – `@Component` that receives
   `List<<X>Strategy>` via constructor injection and dispatches by calling the
   `supports` method:

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class XyzHandler {
    private final List<XyzStrategy> strategies;

    public Result handle(Input in) {
        return strategies.stream()
                .filter(s -> s.supports(in))
                .findFirst()
                .orElseThrow(() -> new DomainException(...))
                .execute(in);
    }
}
```

**Reference implementations in this repo:**
- `permission/PermissionsCheckStrategy` + `PermissionsHandler`
- `converter/FooConverter` + `converter/registry/DocumentConverterRegistry`

### Do / Don't
✅ Add a new behaviour by adding **one** new `@Component` strategy – never touch
the handler.
✅ Throw a domain exception (extends `RuntimeException` or `Exception` from
`exception/`) when no strategy matches.
❌ Do not `if/else` on a type discriminator inside a service – that is a smell
indicating you should introduce a strategy.

## 3. Pattern B — Metrics Filter + Recorder Registry (used in `monitor/`)

For request-level observability use a single `OncePerRequestFilter` that
delegates to a **recorder** chosen by a registry, plus pluggable **parsers**
that extract tags from the request/response.

```
monitor/
├── MetricsFilter.java          # OncePerRequestFilter – measures latency
├── MonitoringConfig.java       # @Configuration: URI Pattern → query type
├── MonitoringConstants.java
├── MetricsTagsHelper.java
├── MetricsTimerHelper.java
├── parsers/                    # one parser per tag (ClientId, TargetFormat, …)
└── recorder/
    ├── MetricsRecorder.java            # interface: recordMetrics(durationMs, req, res)
    ├── MetricsRecorderRegistry.java    # maps queryType → MetricsRecorder
    └── <UseCase>MetricsRecorder.java   # one per business use case
```

Rules:

- The filter measures **elapsed time** in a `try/finally` so failures are still
  recorded.
- Skip `actuator` URIs in `shouldNotFilter`.
- Tag names live in `MonitoringConstants`; do not inline string literals.
- A new metric = **new recorder + new parser** if needed; the filter never changes.

## 4. Pattern C — Operation / Service split

Each public REST endpoint maps to exactly one class in `operation/`:

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class FooOperation {
    private final PermissionsHandler permissionsHandler;
    private final FooService convertDocumentService;

    public FooResponse execute(FooRequest req) {
        permissionsHandler.handle(req.documentId(), req.fileId());
        return convertDocumentService.convert(req);
    }
}
```

- Controllers only do: validate input → call `operation.execute(...)` → map response.
- Services do **one** thing each; compose them inside an operation.

## 4f. Composition over inheritance + Tell-Don't-Ask + Law of Demeter

- **Composition over inheritance.** Inheritance is allowed only when (a) the
  subclass genuinely *is-a* the superclass and (b) the superclass is
  designed for extension (sealed hierarchy, documented protected hooks).
  Otherwise compose: inject the collaborator and delegate. Reference:
  `AbstractReadinessIndicator` is the rare valid case — three abstract
  methods, no state.
- **Tell, don't ask.** A method should *tell* an object what to do, not
  *ask* it for its internals and then act. Smell: `foo.getX().getY().doZ()`.
  Fix: add `foo.doZ()` so `foo` owns the chain.
- **Law of Demeter.** Each method talks only to: its own fields, its
  parameters, objects it just created, or `this`. Walking more than one
  pointer (`a.b().c()`) is a coupling smell; refactor by introducing a
  dedicated method on `b`.

## 4g. Immutability rules

- Prefer **`record`** for DTOs, value objects, events, configuration
  property holders. Records are final, all fields are final, equals/hashCode
  are derived.
- For mutable domain entities (rare), make every collection field
  unmodifiable on the way in and out (`List.copyOf(...)`); never expose the
  raw collection.
- All `@ConfigurationProperties` are records (see `spring-boot-conventions`).
- Constants classes are `final` with `@NoArgsConstructor(access = PRIVATE)`.

## 4h. Visibility (smallest blast radius)

- Default to **package-private** for any class consumers do not strictly
  need.
- Make `public` only types that appear in another package's signature or
  that a downstream module (auto-config, tests in another package) must see.
- In libraries, route internals through an `internal/` sub-package and keep
  them package-private (see `sdk-publishing`).
- `@Component` classes can be package-private — Spring scans them and the
  injection point only depends on the interface they implement.

## 4i. Architecture as code — ArchUnit

Mechanically enforce the package hierarchy + design patterns above. Add the
test dependency:

```xml
<dependency>
    <groupId>com.tngtech.archunit</groupId>
    <artifactId>archunit-junit5</artifactId>
    <version>1.3.0</version>
    <scope>test</scope>
</dependency>
```

Then assert layering, naming and the absence of cycles:

```java
@AnalyzeClasses(packages = "{{basePackage}}")
class ArchitectureTest {

    @ArchTest static final ArchRule layered = layeredArchitecture()
        .consideringAllDependencies()
        .layer("Controller").definedBy("..controller..")
        .layer("Operation").definedBy("..operation..")
        .layer("Service").definedBy("..service..")
        .layer("Client").definedBy("..client..")
        .whereLayer("Controller").mayNotBeAccessedByAnyLayer()
        .whereLayer("Operation").mayOnlyBeAccessedByLayers("Controller")
        .whereLayer("Service").mayOnlyBeAccessedByLayers("Controller", "Operation")
        .whereLayer("Client").mayOnlyBeAccessedByLayers("Service", "Operation", "..health..");

    @ArchTest static final ArchRule noCycles =
        slices().matching("{{basePackage}}.(*)..").should().beFreeOfCycles();

    @ArchTest static final ArchRule controllersAreThin =
        classes().that().resideInAPackage("..controller..")
            .should().haveSimpleNameEndingWith("Controller")
            .andShould().notDependOnClassesThat().resideInAPackage("..client..");

    @ArchTest static final ArchRule webClientLivesInClientOnly =
        noClasses().that().resideOutsideOfPackage("..client..")
            .should().dependOnClassesThat().haveFullyQualifiedName("org.springframework.web.reactive.function.client.WebClient");

    @ArchTest static final ArchRule securityHolderLivesInPermissionOnly =
        noClasses().that().resideOutsideOfPackages("..permission..")
            .should().dependOnClassesThat().haveFullyQualifiedName("org.springframework.security.core.context.SecurityContextHolder");
}
```

These rules turn the conventions from "PR feedback" into "build failure" —
the strongest enforcement you can get.

## 4j. Design pattern catalogue

Beyond the three patterns above (Strategy+Registry, Filter+Recorder, Operation
layering), the project uses the following — apply by name, with the listed
anti-patterns:

| Pattern | When to apply | Anti-pattern |
| --- | --- | --- |
| **Template Method** | A family of classes share a workflow; only specific steps vary. | Re-implementing the workflow in every subclass; missing `final` on the template method. |
| **Decorator** | Add a cross-cutting concern (retry, cache, metrics, logging) to a `Client` without changing it. | Stuffing retry logic into the `Client` itself. |
| **Adapter** | Translate between a remote DTO and the internal domain model. | Leaking remote DTO types into `operation/`. |
| **Builder** | A DTO has > 4 fields or optional combinations. Records remove most need; use `record` + static factory methods first. | Telescoping constructors. |
| **Factory (static)** | A type has multiple named creation paths (`Foo.fromCsv(...)`, `Foo.fromJson(...)`). | Constructor doing parsing. |
| **Specification** | Composable query predicates for a repository. | Endless `findByXAndYOrZ(...)` repository methods. |
| **Observer (Spring events)** | Intra-service fan-out (audit, cache invalidation). | Direct calls between services for non-essential side-effects. |
| **Command** | Long-running, replayable, auditable operation (e.g. a saga step). | Mutating service methods scattered across classes. |
| **Null Object** | A strategy whose "absent" case is a documented no-op (e.g. `NoOpPermissionsCheck`). | `if (handler == null) return;` scattered everywhere. |

## 4k. Pattern D — Monolith to Module

For larger services that are not yet ready for microservices, use **Spring Modulith** or strict package-level isolation to prevent the "Big Ball of Mud".

1. **Modules by package**: `com.example.service.moduleA`, `com.example.service.moduleB`.
2. **Encapsulation**: Only the `api/` sub-package of a module is public. Everything else is package-private.
3. **Internal events**: Use Spring `ApplicationEventPublisher` to communicate between modules. Module A publishes `OrderCreated`, Module B listens. No direct service-to-service calls across module boundaries.

This makes future extraction into a separate microservice trivial.

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
      `@ComponentScan`, `@PropertySource("classpath:application.yaml")`,
      and `@EnableScheduling` if scheduled tasks are needed.
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

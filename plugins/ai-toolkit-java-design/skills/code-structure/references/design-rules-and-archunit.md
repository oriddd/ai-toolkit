# Code Structure — Design rules and ArchUnit

Part of the [`code-structure`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

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
- Constants classes are `final` with `@NoArgsConstructor(access = AccessLevel.PRIVATE)`
  (or Lombok `@UtilityClass`).

## 4h. Visibility (smallest blast radius)

- Default to **package-private** for any class consumers do not strictly
  need.
- Make `public` only types that appear in another package's signature or
  that a downstream module (auto-config, tests in another package) must see.
- In libraries, route internals through an `internal/` sub-package. Classes
  the auto-configuration (a different package) instantiates must be `public` —
  package-private would not compile; keep consumers out by not exporting the
  package (JPMS `exports`, `@API(status = INTERNAL)`) and never returning an
  internal type from `api/` (see `sdk-publishing`). Everything else in
  `internal/` stays package-private.
- `@Component` classes can be package-private — Spring scans them and the
  injection point only depends on the interface they implement.

## 4i. Architecture as code — ArchUnit

Mechanically enforce the package hierarchy + design patterns above. Add the
test dependency:

```xml
<dependency>
    <groupId>com.tngtech.archunit</groupId>
    <artifactId>archunit-junit5</artifactId>
    <version>${archunit.version}</version>
    <scope>test</scope>
</dependency>
```

Declare `archunit.version` in `<properties>` with the current 1.4.x release
and let Renovate bump it — do not hard-code an old version here.

Then assert layering, naming and the absence of cycles:

```java
@AnalyzeClasses(packages = "{{basePackage}}", importOptions = ImportOption.DoNotIncludeTests.class)
class ArchitectureTest {

    @ArchTest static final ArchRule layered = layeredArchitecture()
        .consideringOnlyDependenciesInLayers()   // config/, adapter/, spi/, acl/, domain/, event/ … are not layers, so they are not flagged
        .optionalLayer("Controller").definedBy("..controller..")   // optional: event-driven / scheduler services have none
        .optionalLayer("Operation").definedBy("..operation..")
        .optionalLayer("Service").definedBy("..service..")   // optional: an empty skeleton / thin consumer has none yet
        .optionalLayer("Repository").definedBy("..repository..")
        .optionalLayer("Scheduler").definedBy("..scheduler..")
        .optionalLayer("Health").definedBy("..health..")
        // project-types renames (Type B event-driven / Type C scheduler) — anchored at the base package
        // so client/<dep>/…/handler/ or messaging/consumer/ sub-packages are not mistaken for these layers
        .optionalLayer("Consumer").definedBy("{{basePackage}}.consumer..")
        .optionalLayer("Handler").definedBy("{{basePackage}}.handler..")
        .optionalLayer("Job").definedBy("{{basePackage}}.job..")
        .optionalLayer("Producer").definedBy("{{basePackage}}.producer..")
        .optionalLayer("Client").definedBy("..client..")   // optional: no client/ when the service calls no HTTP downstream (create-repo #11)
        .whereLayer("Controller").mayNotBeAccessedByAnyLayer()
        .whereLayer("Consumer").mayNotBeAccessedByAnyLayer()
        .whereLayer("Operation").mayOnlyBeAccessedByLayers("Controller")
        .whereLayer("Handler").mayOnlyBeAccessedByLayers("Consumer")
        .whereLayer("Job").mayOnlyBeAccessedByLayers("Scheduler")
        .whereLayer("Service").mayOnlyBeAccessedByLayers("Controller", "Operation", "Scheduler", "Consumer", "Handler", "Job")
        .whereLayer("Repository").mayOnlyBeAccessedByLayers("Service", "Operation", "Scheduler", "Handler", "Job")
        .whereLayer("Producer").mayOnlyBeAccessedByLayers("Service", "Operation", "Handler", "Job")
        .whereLayer("Client").mayOnlyBeAccessedByLayers("Service", "Operation", "Repository", "Health", "Handler", "Job");
        // layer names, not package patterns, go in mayOnlyBeAccessedByLayers; only dependencies between two layers are checked,
        // so give every top-level package whose access you want enforced (scheduler, health, …) its own layer;

    @ArchTest static final ArchRule noCycles =
        slices().matching("{{basePackage}}.(*)..").should().beFreeOfCycles();

    @ArchTest static final ArchRule controllersAreNamedController =
        classes().that().resideInAPackage("..controller..")
            .should().haveSimpleNameEndingWith("Controller")
            .allowEmptyShould(true);

    // ArchUnit has no notDependOnClassesThat(): express "must not depend" with noClasses()
    @ArchTest static final ArchRule controllersAreThin =
        noClasses().that().resideInAPackage("..controller..")
            .should().dependOnClassesThat().resideInAPackage("..client..")
            .allowEmptyShould(true);

    // match the whole HTTP-client packages (WebClient, RestClient and their Builders, exchange types, …);
    // client/ wraps them, adapter/ holds HTTP-based vendor adapters, config/ and health/ build the beans
    @ArchTest static final ArchRule webClientLivesInClientOnly =
        noClasses().that().resideOutsideOfPackages("..client..", "..adapter..", "..config..", "..health..")
            .should().dependOnClassesThat().resideInAnyPackage(
                "org.springframework.web.reactive.function.client..",
                "org.springframework.web.client..");

    // the JPA AuditorAware (persistence SecurityAuditorAware) lives in permission/ too; config/AuditConfig only enables auditing
    @ArchTest static final ArchRule securityHolderLivesInPermissionOnly =
        noClasses().that().resideOutsideOfPackage("..permission..")
            .should().dependOnClassesThat().haveFullyQualifiedName("org.springframework.security.core.context.SecurityContextHolder");
}
```

These rules turn the conventions from "PR feedback" into "build failure" —
the strongest enforcement you can get.

## 4j. Design pattern catalogue

Beyond the four patterns A–D (Strategy+Registry, Filter+Recorder, Operation
layering, Monolith to Module), the project uses the following — apply by name, with the listed
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

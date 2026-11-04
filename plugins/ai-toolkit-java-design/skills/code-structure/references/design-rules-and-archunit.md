# this Code Structure Skill — Design rules and ArchUnit

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
@AnalyzeClasses(packages = "{{basePackage}}", importOptions = ImportOption.DoNotIncludeTests.class)
class ArchitectureTest {

    @ArchTest static final ArchRule layered = layeredArchitecture()
        .consideringAllDependencies()
        .layer("Controller").definedBy("..controller..")
        .optionalLayer("Operation").definedBy("..operation..")
        .layer("Service").definedBy("..service..")
        .optionalLayer("Repository").definedBy("..repository..")
        .optionalLayer("Scheduler").definedBy("..scheduler..")
        .optionalLayer("Health").definedBy("..health..")
        .layer("Client").definedBy("..client..")
        .whereLayer("Controller").mayNotBeAccessedByAnyLayer()
        .whereLayer("Operation").mayOnlyBeAccessedByLayers("Controller")
        .whereLayer("Service").mayOnlyBeAccessedByLayers("Controller", "Operation", "Scheduler")
        .whereLayer("Repository").mayOnlyBeAccessedByLayers("Service", "Operation", "Scheduler")
        .whereLayer("Client").mayOnlyBeAccessedByLayers("Service", "Operation", "Repository", "Health");
        // layer names, not package patterns, go in mayOnlyBeAccessedByLayers; code outside every layer that touches a layer is a violation,
        // so give each real top-level package (scheduler, health, …) a layer or an ignoreDependency;

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

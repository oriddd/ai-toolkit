# Pluggable Architecture Skill — Enforcement and how other skills plug in

Part of the [`pluggable-architecture`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 6. Enforce it mechanically (ArchUnit)

Turn the "no vendor imports outside adapters" rule into a **build failure**, not
PR feedback. Extend the `code-structure` ArchUnit suite:

```java
@AnalyzeClasses(packages = "{{basePackage}}")
class PluggabilityRulesTest {

    // The domain/application layer may depend ONLY on ports, never on adapters.
    @ArchTest static final ArchRule domainDependsOnPortsOnly =
        noClasses().that().resideOutsideOfPackages("..adapter..", "..config..")
            .should().dependOnClassesThat().resideInAPackage("..adapter..");

    // Port (spi) packages must be free of any third-party vendor types.
    @ArchTest static final ArchRule portsAreVendorFree =
        noClasses().that().resideInAPackage("..spi..")
            .should().dependOnClassesThat()
            .resideInAnyPackage("org.springframework.data.redis..", "com.datadoghq..",
                                "oracle.jdbc..", "org.apache.kafka..", "software.amazon.awssdk..");

    // Every adapter implements a port and lives under adapter/<vendor>/.
    @ArchTest static final ArchRule adaptersImplementPorts =
        classes().that().resideInAPackage("..adapter..")
            .and().haveSimpleNameEndingWith("Adapter")
            .should().implement(JavaClass.Predicates.resideInAPackage("..spi.."));
}
```

(Extend the forbidden-vendor-package list per project. The exact vendors are
examples — the rule is "no vendor types leak into `spi/`".)

## 7. How each existing skill plugs in

This skill defines the *frame*; the concrete skills provide the *bricks*. When
you apply one of these, expose its technology as a port + adapters:

| Capability (skill) | Port example | Adapter examples (illustrative, not exhaustive) |
| --- | --- | --- |
| `persistence` | `RepositoryPort` / dialect-isolated repositories | any relational dialect, any document store |
| `observability` | `MetricsPort`, `TracingPort` | any scrape-based or push-based backend |
| `messaging` | `EventPublisherPort`, `EventConsumerPort` | any broker / streaming platform |
| `external-client` | `<Domain>ClientPort` | HTTP, gRPC, file, in-process fake |
| `rate-limiting` | `RateLimiterPort` | local in-memory, distributed |
| `data-privacy` | `EncryptionPort`, `KeyProviderPort` | any KMS / vault / local key |
| `feature-flags` | `FeatureTogglePort` | local config, any remote flag service |
| `permissions` | existing `CallerContextResolver` SPI | any identity/token shape |

> The table is deliberately vendor-neutral: the point is the **shape**, not the
> specific tools. New capabilities follow the same three-layer recipe.

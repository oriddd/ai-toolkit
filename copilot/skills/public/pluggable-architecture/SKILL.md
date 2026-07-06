---
name: pluggable-architecture
description: Treat every external technology integration (cache, database, metrics backend, message broker, object store, secret manager, identity provider, …) as a swappable lego-brick behind a stable port interface, selectable and composable purely by configuration. Domain and application code depend only on ports; concrete vendor adapters are wired by Spring conditional beans and can be replaced, or run several-at-once, without touching business logic. Apply this skill before writing ANY code that talks to an external tool or technology.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: [code-structure, spring-boot-conventions]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-30
---

# Pluggable Architecture Skill (public)

The single most important architectural rule in this catalogue: **no business
code is ever coupled to a concrete technology.** Every integration with an
external tool — a cache, a database dialect, a metrics backend, a broker, an
object store, a secret manager, an identity provider, a feature-flag service —
is consumed through a **port** (a project-owned interface) and supplied by one
or more **adapters** (vendor-specific implementations) that are chosen **by
configuration**, never by editing code.

This is the **Ports & Adapters (Hexagonal)** pattern, hardened into a
non-negotiable and combined with Spring's conditional wiring so that:

- Any technology can be **swapped** for an alternative by changing a property
  (and/or a dependency on the classpath) — zero changes to domain/application
  code.
- A capability can run with **multiple providers at once** (broadcast,
  failover, priority, weighted) when the use case demands it — again by
  configuration only.
- The codebase reads like an **open-source SDK**: stable interfaces, replaceable
  internals, SOLID by construction (DIP + OCP enforced mechanically).

> This skill is the *policy*. Concrete skills (`persistence`, `observability`,
> `messaging`, `external-client`, `rate-limiting`, `data-privacy`, …) are the
> *bindings* — each one must expose its technology through a port that obeys the
> rules below.

## When to use

Apply this skill **whenever** a task introduces or modifies contact with an
external technology or third-party library. If the agent is about to type an
`import` for a vendor SDK (Redis, Datadog, Oracle JDBC, Kafka, AWS S3, …) in
anything other than an adapter or auto-configuration class, **stop** and apply
this skill first.

## 1. The three layers of every capability

For a capability named `X`, generate exactly three concerns in separate places:

```
<basePackage>/
├── spi/                                  # the PORT — owned by us, vendor-free
│   └── x/
│       ├── XPort.java                     # interface the domain depends on
│       ├── XKey.java / XResult.java …     # port DTOs (records), vendor-free
│       └── XProviderException.java        # port-level exception type
├── adapter/                               # the ADAPTERS — one sub-package per vendor
│   └── x/
│       ├── redis/   RedisXAdapter.java     # implements XPort using a vendor SDK
│       ├── infinispan/ InfinispanXAdapter.java
│       └── noop/    NoOpXAdapter.java      # safe default / disabled mode
└── config/                                # the WIRING — conditional selection only
    └── x/
        └── XAutoConfiguration.java         # @ConditionalOn… picks the adapter(s)
```

Rules:

- **`spi/` (the port)** contains *only* project-owned types. **No vendor import
  is ever allowed here.** No `org.springframework.data.redis.*`, no
  `com.datadoghq.*`, no `oracle.jdbc.*`. The port speaks the project's
  language, not the vendor's.
- **`adapter/<vendor>/`** is the *only* place a vendor SDK may be imported. Each
  adapter is `package-private` where possible and registered as a bean by the
  capability's auto-configuration.
- **`config/x/`** holds the conditional wiring and nothing else — no business
  logic, no vendor calls, just bean definitions guarded by `@ConditionalOn…`.

## 2. The port contract (DIP + OCP)

```java
// spi/x/CachePort.java  — vendor-free, this is what the domain depends on
public interface CachePort {
    Optional<byte[]> get(CacheKey key);
    void put(CacheKey key, byte[] value, Duration ttl);
    void evict(CacheKey key);
    String providerId();           // for observability + composition routing
}
```

- The port is the **stable contract**. It changes only on a deliberate, SemVer
  major decision (see `sdk-publishing`, `release-versioning`).
- Port method signatures use **port DTOs** (records) and JDK types — never
  vendor types, never framework types. An adapter that needs a vendor type
  *translates* at its own boundary (the Adapter pattern from
  `code-structure` §4j).
- The port carries a `providerId()` so logs, metrics, and composition policies
  can identify which brick handled a call.

## 3. Config-driven single-provider selection

The default mode: exactly one adapter is active, chosen by a property.

```java
// config/x/CacheAutoConfiguration.java
@AutoConfiguration
@EnableConfigurationProperties(CacheProperties.class)
public class CacheAutoConfiguration {

    @Bean
    @ConditionalOnProperty(prefix = "platform.cache", name = "provider", havingValue = "redis")
    @ConditionalOnClass(name = "org.springframework.data.redis.core.RedisTemplate")
    CachePort redisCachePort(RedisTemplate<String, byte[]> template) {
        return new RedisCacheAdapter(template);
    }

    @Bean
    @ConditionalOnProperty(prefix = "platform.cache", name = "provider", havingValue = "infinispan")
    @ConditionalOnClass(name = "org.infinispan.Cache")
    CachePort infinispanCachePort(EmbeddedCacheManager manager) {
        return new InfinispanCacheAdapter(manager);
    }

    @Bean
    @ConditionalOnMissingBean(CachePort.class)        // safe fallback
    CachePort noOpCachePort() {
        return new NoOpCacheAdapter();
    }
}
```

```yaml
# application.yaml — swap the whole technology with ONE line
platform:
  cache:
    provider: redis        # redis | infinispan | noop
```

Selection levers (use in this order of preference):

1. **`@ConditionalOnProperty`** — the explicit, documented switch the operator
   flips. Always the primary mechanism.
2. **`@ConditionalOnClass`** — guard so an adapter silently backs off when its
   vendor SDK is not on the classpath (lets consumers exclude a dependency to
   shrink the image).
3. **`@ConditionalOnMissingBean`** — provide a default (often `NoOp`) so the
   context always has *a* `CachePort`, and so a consumer can override any brick
   by declaring their own bean (the lego-brick override contract from
   `sdk-publishing`).
4. **`@Primary` / `@Profile`** — only for deliberate local/dev overrides, never
   as the main selection path.

## 4. Multi-provider composition (one or many bricks)

When a capability must use **several providers at once**, the port stays the
same — you add a **composite adapter** that itself implements the port and
fans out to the delegates. The domain never knows the difference.

```java
// adapter/x/composite/CompositeMetricsAdapter.java
public class CompositeMetricsAdapter implements MetricsPort {
    private final List<MetricsPort> delegates;          // ordered via @Order
    private final CompositionMode mode;                 // BROADCAST | FAILOVER | PRIORITY | WEIGHTED

    @Override public void record(MetricSample s) {
        switch (mode) {
            case BROADCAST -> delegates.forEach(d -> safe(() -> d.record(s)));
            case FAILOVER  -> firstThatSucceeds(s);
            case PRIORITY  -> delegates.get(0).record(s);
            case WEIGHTED  -> weightedPick().record(s);
        }
    }
}
```

```yaml
platform:
  metrics:
    mode: broadcast              # single | broadcast | failover | priority | weighted
    providers: [prometheus, datadog]
```

Composition rules:

- The composite is **just another adapter** behind the same port — wired by the
  same `config/x` auto-configuration when `mode != single`.
- **Failure isolation:** in `broadcast`/`failover`, one provider failing must
  not fail the others. Wrap each delegate call (`safe(...)`) and emit a metric +
  log on failure (see `observability`, `resilience-patterns`).
- **Ordering** is explicit via Spring `@Order` on each adapter bean, never
  classpath-accidental.
- A capability that is inherently single-writer (e.g. the primary transactional
  database) must document that `broadcast` is **not** a valid mode for it.

## 5. Configuration shape

One typed `@ConfigurationProperties` record per capability (see
`spring-boot-conventions` §1):

```java
@ConfigurationProperties(prefix = "platform.cache")
public record CacheProperties(
        @NotNull Provider provider,                 // enum: REDIS, INFINISPAN, NOOP
        CompositionMode mode,                       // default SINGLE
        List<String> providers,                     // for multi-provider modes
        Duration defaultTtl) {
    public enum Provider { REDIS, INFINISPAN, NOOP }
    public CacheProperties {
        if (mode == null) mode = CompositionMode.SINGLE;
        if (providers == null) providers = List.of();
    }
}
```

- The **provider key is an enum**, so a typo fails fast at startup, and the
  valid set is self-documenting in IDE autocomplete (configuration metadata).
- Every capability publishes its `platform.<capability>.*` keys in the README
  and in `additional-spring-configuration-metadata.json` (see `sdk-publishing`).

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

## 8. Definition of done (per capability)

Before returning a diff that touches an external technology, verify:

- [ ] A **port interface** exists under `spi/<capability>/`, free of vendor and
      framework types.
- [ ] **1..N adapters** exist under `adapter/<capability>/<vendor>/`, each the
      *only* place its vendor SDK is imported.
- [ ] A **safe default** adapter (`NoOp` or local) is provided via
      `@ConditionalOnMissingBean`.
- [ ] Selection/composition lives **only** in `config/<capability>/…` and is
      driven by a typed `@ConfigurationProperties` (enum provider key).
- [ ] Swapping providers requires **only** a property change (and optionally a
      dependency swap) — **no** domain/application edits.
- [ ] **Multi-provider mode** is either supported (with failure isolation) or
      explicitly documented as unsupported for that capability.
- [ ] **ArchUnit** rules from §6 cover the new capability and pass.
- [ ] **Contract tests** (see `adapter-contract-tests`) validate that *every*
      adapter satisfies the same port behaviour.
- [ ] `platform.<capability>.*` keys are documented in the README and in
      configuration metadata.

## Do / Don't

✅ Depend on a **port interface** from domain/application code — always.
✅ Put the **only** vendor import inside `adapter/<vendor>/`.
✅ Select and compose providers **by configuration** (`@ConditionalOnProperty`
   + typed enum), with a `@ConditionalOnMissingBean` safe default.
✅ Make every brick replaceable by a consumer-supplied bean of the same port
   type (lego-brick override).
✅ Support multi-provider fan-out via a **composite adapter**, with per-provider
   failure isolation.
✅ Enforce "no vendor leakage into `spi/`" with ArchUnit so it fails the build.
❌ Never import a vendor SDK in `service/`, `operation/`, `controller/`,
   `domain/`, or `spi/`.
❌ Never branch on the technology inside business logic
   (`if (provider == REDIS) …`) — that belongs in the composite/config layer.
❌ Never make the domain aware of *how many* providers are active.
❌ Never hard-wire a single vendor with `new RedisTemplate(...)` outside an
   adapter/config class.
❌ Never let a provider's failure in `broadcast` mode take down the others.

## Cross-references

- [`code-structure`](../code-structure/SKILL.md) — package hierarchy, Adapter /
  Strategy patterns, ArchUnit enforcement this skill builds on.
- [`spring-boot-conventions`](../spring-boot-conventions/SKILL.md) — typed
  `@ConfigurationProperties` and `@Conditional*` wiring.
- [`sdk-publishing`](../sdk-publishing/SKILL.md) — producer-side lego-brick
  (`@ConditionalOnMissingBean` defaults, configuration metadata, SemVer).
- [`external-client`](../external-client/SKILL.md) — consumer-side adapter stack
  for a single downstream.
- [`adapter-contract-tests`](../adapter-contract-tests/SKILL.md) — TCK-style
  shared tests proving every adapter is interchangeable.
- [`observability`](../observability/SKILL.md),
  [`persistence`](../persistence/SKILL.md),
  [`messaging`](../messaging/SKILL.md),
  [`rate-limiting`](../rate-limiting/SKILL.md) — capabilities that bind to this
  policy.


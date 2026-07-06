---
name: adapter-contract-tests
description: Prove the lego-brick contract — write one shared, vendor-neutral abstract test suite (a TCK) per port interface, then run it against EVERY adapter (Redis vs Infinispan, Prometheus vs Datadog, Postgres vs Oracle, …) so that swapping a provider cannot change business behaviour. Each adapter subclasses the suite, supplies its own instance (often via Testcontainers), and must pass identical assertions. Use whenever a port gains a new adapter or an existing adapter changes.
tier: should
applies_to: [rest, event, scheduler, library, monolith]
depends_on: [pluggable-architecture, unit-tests]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-30
---

# Adapter Contract Tests Skill (public)

A port is only a real lego-brick interface if **every adapter behind it behaves
identically**. This skill codifies that guarantee with a **Technology
Compatibility Kit (TCK)**: one abstract test class per port that encodes the
port's behavioural contract, and one tiny concrete subclass per adapter that
plugs in its implementation. Swapping providers in production is safe precisely
because the same assertions pass for all of them in CI.

This is the test-side counterpart of the [`pluggable-architecture`](../pluggable-architecture/SKILL.md)
skill: that skill defines the ports and adapters; this skill proves they are
interchangeable.

## When to use

- A **new adapter** is added behind an existing port.
- An **existing adapter** is modified.
- A **port contract** changes (the TCK is updated first, then every adapter is
  made green again — TCK as executable specification).

## 1. Shape

```
src/test/java/<basePackage>/
└── spi/x/
    ├── CachePortContract.java          # abstract TCK — all behavioural assertions
    └── adapters/
        ├── RedisCacheAdapterContractTest.java        # extends CachePortContract
        ├── InfinispanCacheAdapterContractTest.java   # extends CachePortContract
        └── NoOpCacheAdapterContractTest.java         # extends CachePortContract (documents no-op semantics)
```

One abstract contract per port; one concrete subclass per adapter. The
subclasses contain **no assertions** — only the wiring that produces an instance
of the port.

## 2. The abstract contract (TCK)

The abstract class owns **every** behavioural assertion and exposes a single
factory method the subclass must implement.

```java
public abstract class CachePortContract {

    /** Each adapter supplies a ready-to-use instance (real backend or testcontainer). */
    protected abstract CachePort newCache();

    private CachePort cache;

    @BeforeEach void setUp() { cache = newCache(); }

    @Test
    void get_missingKey_returnsEmpty() {
        assertThat(cache.get(new CacheKey("absent"))).isEmpty();
    }

    @Test
    void put_thenGet_returnsStoredValue() {
        var key = new CacheKey("k1");
        cache.put(key, "v1".getBytes(UTF_8), Duration.ofMinutes(5));
        assertThat(cache.get(key)).map(String::new).contains("v1");
    }

    @Test
    void evict_removesValue() {
        var key = new CacheKey("k2");
        cache.put(key, "v".getBytes(UTF_8), Duration.ofMinutes(5));
        cache.evict(key);
        assertThat(cache.get(key)).isEmpty();
    }

    @Test
    void providerId_isStableAndNonBlank() {
        assertThat(cache.providerId()).isNotBlank();
    }

    // Add one test per behavioural guarantee in the port's Javadoc:
    // TTL expiry, overwrite semantics, null/empty handling, concurrency, …
}
```

Rules:

- **All assertions live here, once.** A new behavioural guarantee is added in
  the TCK and automatically enforced for every adapter.
- The TCK speaks **only the port's language** (port DTOs + JDK types). It must
  not import any vendor SDK — exactly like the port itself.
- Cover the same dimensions the `unit-tests` skill requires: happy path, every
  branch, boundaries (empty, TTL=0, large value), and error translation (vendor
  failure → port exception type).

## 3. The per-adapter subclass

Each adapter contributes only the instance — usually backed by Testcontainers
for real I/O adapters (see `integration-tests`).

```java
@Testcontainers
class RedisCacheAdapterContractTest extends CachePortContract {

    @Container
    static final GenericContainer<?> REDIS =
        new GenericContainer<>("redis:7-alpine").withExposedPorts(6379);

    @Override
    protected CachePort newCache() {
        var template = redisTemplate(REDIS.getHost(), REDIS.getMappedPort(6379));
        return new RedisCacheAdapter(template);
    }
}
```

```java
class NoOpCacheAdapterContractTest extends CachePortContract {
    @Override protected CachePort newCache() { return new NoOpCacheAdapter(); }
    // NoOp legitimately overrides the tests whose semantics differ (e.g. get always empty),
    // documenting exactly where the no-op contract diverges — and why.
}
```

- In-memory adapters run in the unit-test phase (Surefire); adapters needing a
  real backend run in the integration phase (Failsafe) via Testcontainers — see
  `integration-tests` for the Surefire/Failsafe split.
- A subclass may legitimately `@Override` a TCK test **only** when the adapter's
  documented semantics differ (e.g. a `NoOp` cache). Any such override must
  carry a comment explaining the divergence; everything else stays inherited.

## 4. Composite-adapter contract

The composite from `pluggable-architecture` §4 is *also* an adapter, so it gets
its own contract subclass plus composition-specific tests:

```java
class CompositeMetricsAdapterContractTest extends MetricsPortContract {
    @Override protected MetricsPort newMetrics() {
        return new CompositeMetricsAdapter(List.of(new FakeMetrics("a"), new FakeMetrics("b")),
                                           CompositionMode.BROADCAST);
    }

    @Test
    void broadcast_oneDelegateFails_othersStillReceive() {
        var ok = new FakeMetrics("ok");
        var boom = new ThrowingMetrics("boom");
        var composite = new CompositeMetricsAdapter(List.of(boom, ok), CompositionMode.BROADCAST);
        composite.record(sample());
        assertThat(ok.recorded()).hasSize(1);          // failure isolation proven
    }
}
```

Composition guarantees to assert: failure isolation (broadcast/failover),
ordering (priority), and that the domain-visible result is independent of how
many delegates are active.

## 5. Wire it into the build

- TCK + in-memory adapter contracts run on every `mvn test`.
- Real-backend adapter contracts run on `mvn verify` (Failsafe + Testcontainers).
- Treat a missing adapter contract as a **build gap**: an ArchUnit / custom
  check can assert that every class ending in `Adapter` has a matching
  `*ContractTest`.

```java
@ArchTest static final ArchRule everyAdapterHasAContractTest =
    classes().that().haveSimpleNameEndingWith("Adapter")
        .should(haveAMatchingContractTest());   // custom condition: <Name>ContractTest exists
```

## Do / Don't

✅ Put **all** behavioural assertions in the abstract TCK, once.
✅ Make each adapter a thin subclass that only supplies an instance.
✅ Back real-I/O adapters with Testcontainers in the integration phase.
✅ Give the composite adapter its own contract + failure-isolation tests.
✅ Fail the build when an `Adapter` has no matching `ContractTest`.
❌ Never copy-paste assertions into each adapter's test — they will drift.
❌ Never import a vendor SDK into the abstract TCK.
❌ Never silently `@Override` a contract test without documenting the divergence.
❌ Never let an adapter pass by weakening the shared assertions.

## Cross-references

- [`pluggable-architecture`](../pluggable-architecture/SKILL.md) — defines the
  ports and adapters this skill verifies.
- [`unit-tests`](../unit-tests/SKILL.md) — assertion style, coverage dimensions,
  parameterized cases the TCK reuses.
- [`integration-tests`](../integration-tests/SKILL.md) — Testcontainers +
  Surefire/Failsafe split for real-backend adapters.
- [`sdk-publishing`](../sdk-publishing/SKILL.md) — `ApplicationContextRunner`
  tests proving the auto-config selects and backs off correctly.


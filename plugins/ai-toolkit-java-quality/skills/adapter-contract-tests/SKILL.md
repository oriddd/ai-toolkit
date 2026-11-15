---
name: adapter-contract-tests
description: >
  Java / Spring Boot adapter contract tests — one abstract, vendor-neutral suite (TCK) per port, subclassed by every
  adapter (often with Testcontainers) so swapping a provider cannot change behaviour. Use when a port gains a new
  adapter or an adapter changes.
tier: should
applies_to: [rest, event, scheduler, library, monolith]
depends_on: [pluggable-architecture, unit-tests]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-11
---

# Adapter Contract Tests Skill
A port is only a real lego-brick interface if **every adapter behind it behaves
identically**. This skill codifies that guarantee with a **Technology
Compatibility Kit (TCK)**: one abstract test class per port that encodes the
port's behavioural contract, and one tiny concrete subclass per adapter that
plugs in its implementation. Swapping providers in production is safe precisely
because the same assertions pass for all of them in CI.

This is the test-side counterpart of the `pluggable-architecture`
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
├── spi/cache/
│   └── CachePortContract.java          # abstract TCK — all behavioural assertions
└── adapter/cache/                       # mirrors main: adapter/<capability>/<vendor>/
    ├── redis/RedisCacheAdapterContractIT.java              # extends CachePortContract (Testcontainers → *IT, Failsafe)
    ├── infinispan/InfinispanCacheAdapterContractTest.java  # extends CachePortContract
    └── noop/NoOpCacheAdapterContractTest.java              # extends CachePortContract (documents no-op semantics)
```

One abstract contract per port; one concrete subclass per adapter. The
subclasses contain **no copies of the shared assertions** — only the wiring that
produces an instance of the port. The two exceptions are documented overrides
(§3) and composition-specific tests for a composite adapter (§4).

## 2. The abstract contract (TCK)

The abstract class owns **every** behavioural assertion and exposes a single
factory method the subclass must implement.

```java
public abstract class CachePortContract {

    /** Each adapter supplies a ready-to-use instance (real backend or testcontainer). */
    protected abstract CachePort newCache();

    /** Wipe backend state shared across tests (e.g. a static Redis container); no-op for in-memory adapters. */
    protected abstract void clearBackend();

    protected CachePort cache;

    @BeforeEach protected void setUp() { clearBackend(); cache = newCache(); }

    @Test
    protected void get_missingKey_returnsEmpty() {
        assertThat(cache.get(new CacheKey("absent"))).isEmpty();
    }

    @Test
    protected void get_afterPut_returnsStoredValue() {
        var key = new CacheKey("k1");
        cache.put(key, "v1".getBytes(UTF_8), Duration.ofMinutes(5));
        assertThat(cache.get(key)).map(b -> new String(b, UTF_8)).contains("v1");
    }

    @Test
    protected void evict_storedKey_removesValue() {
        var key = new CacheKey("k2");
        cache.put(key, "v".getBytes(UTF_8), Duration.ofMinutes(5));
        cache.evict(key);
        assertThat(cache.get(key)).isEmpty();
    }

    @Test
    protected void providerId_anyAdapter_isStableAndNonBlank() {
        assertThat(cache.providerId()).isNotBlank().isEqualTo(cache.providerId());
    }

    // Add one test per behavioural guarantee in the port's Javadoc:
    // TTL expiry, overwrite semantics, null/empty handling, concurrency, …
}
```

Rules:

- **Test methods and `setUp` are `protected`.** The TCK lives in `spi/<capability>/`, the subclasses in
  `adapter/<capability>/<vendor>/` — another package. A package-private test method cannot be overridden from there:
  `@Override` does not compile, and without it JUnit still runs the TCK's assertion next to the subclass's method.
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
@Tag("integration")
class RedisCacheAdapterContractIT extends CachePortContract {   // *IT: Failsafe runs it, Surefire skips it

    @Container
    static final GenericContainer<?> REDIS =
        new GenericContainer<>("redis:7-alpine").withExposedPorts(6379);

    private RedisTemplate<String, byte[]> template;

    @Override
    protected CachePort newCache() {
        return new RedisCacheAdapter(template);
    }

    @Override
    protected void clearBackend() {
        template = redisTemplate(REDIS.getHost(), REDIS.getMappedPort(6379));
        template.execute((RedisCallback<Void>) c -> { c.serverCommands().flushDb(); return null; });
    }

    /** Outside a Spring context the factory and template must be initialised and started by hand. */
    private static RedisTemplate<String, byte[]> redisTemplate(String host, int port) {
        var factory = new LettuceConnectionFactory(new RedisStandaloneConfiguration(host, port));
        factory.afterPropertiesSet();
        factory.start();
        var t = new RedisTemplate<String, byte[]>();
        t.setConnectionFactory(factory);
        t.setKeySerializer(RedisSerializer.string());
        t.setValueSerializer(RedisSerializer.byteArray());
        t.afterPropertiesSet();
        return t;
    }
}
```

(In a real suite create the template once per class and close the factory in
`@AfterAll`; the per-test creation above keeps the example short.)

```java
class NoOpCacheAdapterContractTest extends CachePortContract {
    @Override protected CachePort newCache() { return new NoOpCacheAdapter(); }
    @Override protected void clearBackend() { }   // nothing is stored

    // Divergence: a no-op cache never stores anything, so a read after a put is a miss.
    // That is its documented contract (pluggable-architecture safe default), not a bug.
    @Override
    @Test
    protected void get_afterPut_returnsStoredValue() {
        var key = new CacheKey("k1");
        cache.put(key, "v1".getBytes(UTF_8), Duration.ofMinutes(5));
        assertThat(cache.get(key)).isEmpty();
    }
}
```

- In-memory adapters run in the unit-test phase (Surefire); adapters needing a
  real backend run in the integration phase (Failsafe) via Testcontainers — see
  `integration-tests` for the Surefire/Failsafe split. Name the real-backend
  subclasses `*ContractIT` (a `*ContractTest` suffix would make Surefire run
  them in `mvn test`); in-memory ones keep `*ContractTest`.
- A subclass may legitimately `@Override` a TCK test **only** when the adapter's
  documented semantics differ (e.g. a `NoOp` cache). Any such override must
  carry a comment explaining the divergence; everything else stays inherited. It keeps `@Override`, `@Test` and the
  `protected` modifier, so the compiler proves it really replaces the TCK method.

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
  `*ContractTest` (or `*ContractIT` for real-backend adapters).

The check must see **test** classes, so it cannot use the usual
`ImportOption.DoNotIncludeTests` import. A plain JUnit test with its own
`ClassFileImporter` (main + test classes on the test classpath) does it:

```java
class AdapterContractCoverageTest {

    @Test
    void everyAdapter_withoutContractTest_failsTheBuild() {
        JavaClasses all = new ClassFileImporter().importPackages("{{basePackage}}");   // main + test classes
        Set<String> names = all.stream().map(JavaClass::getSimpleName).collect(toSet());

        List<String> missing = all.stream()
            .filter(c -> c.getSimpleName().endsWith("Adapter"))
            .filter(c -> !c.isInterface() && !c.getModifiers().contains(JavaModifier.ABSTRACT))
            .filter(c -> !names.contains(c.getSimpleName() + "ContractTest")
                      && !names.contains(c.getSimpleName() + "ContractIT"))
            .map(JavaClass::getName)
            .toList();

        assertThat(missing).as("adapters without <Name>ContractTest / <Name>ContractIT").isEmpty();
    }
}
```

## Do / Don't

✅ Put **all** behavioural assertions in the abstract TCK, once.
✅ Make each adapter a thin subclass that only supplies an instance.
✅ Back real-I/O adapters with Testcontainers in the integration phase.
✅ Give the composite adapter its own contract + failure-isolation tests.
✅ Fail the build when an `Adapter` has no matching `ContractTest` / `ContractIT`.
❌ Never copy-paste assertions into each adapter's test — they will drift.
❌ Never import a vendor SDK into the abstract TCK.
❌ Never silently `@Override` a contract test without documenting the divergence.
❌ Never let an adapter pass by weakening the shared assertions.

## Cross-references

- `pluggable-architecture` — defines the
  ports and adapters this skill verifies.
- `unit-tests` — assertion style, coverage dimensions,
  parameterized cases the TCK reuses.
- `integration-tests` — Testcontainers +
  Surefire/Failsafe split for real-backend adapters.
- `sdk-publishing` — `ApplicationContextRunner`
  tests proving the auto-config selects and backs off correctly.


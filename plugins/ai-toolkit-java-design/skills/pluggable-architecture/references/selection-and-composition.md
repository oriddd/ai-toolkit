# Pluggable Architecture Skill — Provider selection, composition and configuration

Part of the [`pluggable-architecture`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 3. Config-driven single-provider selection

The default mode: exactly one adapter is active, chosen by a property.

```java
// config/x/CacheAutoConfiguration.java
@AutoConfiguration
@EnableConfigurationProperties(CacheProperties.class)
public class CacheAutoConfiguration {

    // Vendor-typed beans live in nested static classes: @ConditionalOnClass on the CLASS is checked
    // before its methods are introspected, so an absent SDK never causes NoClassDefFoundError
    // (on a @Bean method with vendor-typed parameters it would).
    @Configuration(proxyBeanMethods = false)
    @ConditionalOnClass(name = "org.springframework.data.redis.core.RedisTemplate")
    @ConditionalOnProperty(prefix = "platform.cache", name = "provider", havingValue = "redis")
    static class RedisCacheConfiguration {
        @Bean
        CachePort redisCachePort(RedisTemplate<String, byte[]> template) {
            return new RedisCacheAdapter(template);
        }
    }

    @Configuration(proxyBeanMethods = false)
    @ConditionalOnClass(name = "org.infinispan.Cache")
    @ConditionalOnProperty(prefix = "platform.cache", name = "provider", havingValue = "infinispan")
    static class InfinispanCacheConfiguration {
        @Bean
        CachePort infinispanCachePort(EmbeddedCacheManager manager) {
            return new InfinispanCacheAdapter(manager);
        }
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

Register the auto-configuration in
`src/main/resources/META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`
(one fully-qualified class name per line). Boot then processes it **after** the application's own
configuration, so `@ConditionalOnMissingBean` sees consumer overrides, and `@SpringBootApplication`'s
`AutoConfigurationExcludeFilter` stops component scanning of `config/x/` from loading it a second time, too early.

Selection levers (use in this order of preference):

1. **`@ConditionalOnProperty`** — the explicit, documented switch the operator
   flips. Always the primary mechanism.
2. **`@ConditionalOnClass`** — guard so an adapter silently backs off when its
   vendor SDK is not on the classpath (lets consumers exclude a dependency to
   shrink the image). Put it on a nested `@Configuration` class, not on a `@Bean`
   method whose signature uses vendor types.
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
@Validated                                          // without it @NotNull is never checked
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

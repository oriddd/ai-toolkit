# Pluggable Architecture Skill — Provider selection, composition and configuration

Part of the [`pluggable-architecture`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 3. Config-driven single-provider selection

The default mode: exactly one adapter is active, chosen by a property.

```java
// config/cache/CacheAutoConfiguration.java — selection only, no vendor imports
@AutoConfiguration
@EnableConfigurationProperties(CacheProperties.class)
@Import({RedisCacheConfiguration.class, InfinispanCacheConfiguration.class})  // processed before the fallback below
public class CacheAutoConfiguration {

    @Bean
    @ConditionalOnMissingBean(CachePort.class)        // safe fallback — cache is a harmless capability
    CachePort noOpCachePort() {
        return new NoOpCacheAdapter();
    }
}
```

```java
// adapter/cache/redis/RedisCacheConfiguration.java — with the adapter, the only place Redis types are imported.
// Vendor-typed beans live in their own configuration class: @ConditionalOnClass on the CLASS is checked
// before its methods are introspected, so an absent SDK never causes NoClassDefFoundError
// (on a @Bean method with vendor-typed parameters it would).
@Configuration(proxyBeanMethods = false)
@ConditionalOnClass(name = "org.springframework.data.redis.core.RedisTemplate")
@ConditionalOnProperty(prefix = "platform.cache", name = "provider", havingValue = "redis")
public class RedisCacheConfiguration {

    @Bean
    CachePort redisCachePort(RedisConnectionFactory connectionFactory) {
        // Boot auto-configures only RedisTemplate<Object, Object> and StringRedisTemplate,
        // so the adapter builds the typed template it needs from the connection factory.
        RedisTemplate<String, byte[]> template = new RedisTemplate<>();
        template.setConnectionFactory(connectionFactory);
        template.setKeySerializer(RedisSerializer.string());
        template.setValueSerializer(RedisSerializer.byteArray());
        template.afterPropertiesSet();
        return new RedisCacheAdapter(template);   // RedisCacheAdapter is package-private in the same package
    }
}

// adapter/cache/infinispan/InfinispanCacheConfiguration.java
@Configuration(proxyBeanMethods = false)
@ConditionalOnClass(name = "org.infinispan.Cache")
@ConditionalOnProperty(prefix = "platform.cache", name = "provider", havingValue = "infinispan")
public class InfinispanCacheConfiguration {

    @Bean
    CachePort infinispanCachePort(EmbeddedCacheManager manager) {
        return new InfinispanCacheAdapter(manager);
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
   shrink the image). Put it on the vendor `@Configuration` class, not on a `@Bean`
   method whose signature uses vendor types.
3. **`@ConditionalOnMissingBean`** — provide a default (often `NoOp`) so the
   context always has *a* `CachePort`, and so a consumer can override any brick
   by declaring their own bean (the lego-brick override contract from
   `sdk-publishing`). Use a NoOp default only for harmless capabilities (cache,
   metrics). For security-relevant ports (`EncryptionPort`, `KeyProviderPort`,
   `SecretPort`, identity) declare **no** fallback, so a missing or misspelt
   provider fails startup instead of silently disabling protection.
4. **`@Primary` / `@Profile`** — only for deliberate local/dev overrides, never
   as the main selection path.

## 4. Multi-provider composition (one or many bricks)

When a capability must use **several providers at once**, the port stays the
same — you add a **composite adapter** that itself implements the port and
fans out to the delegates. The domain never knows the difference.

```java
// adapter/secret/composite/CompositeSecretAdapter.java
@Slf4j
@RequiredArgsConstructor
public class CompositeSecretAdapter implements SecretPort {
    private final List<SecretPort> delegates;          // ordered via @Order (ObjectProvider.orderedStream())
    private final CompositionMode mode;                // wired only when mode != SINGLE

    @Override
    public Optional<String> lookup(SecretKey key) {
        return switch (mode) {
            case PRIORITY -> delegates.get(0).lookup(key);
            case FAILOVER -> firstThatSucceeds(key);
            // a read has nothing to broadcast or weight; reject the mode instead of guessing
            case SINGLE, BROADCAST, WEIGHTED ->
                    throw new IllegalStateException("Composition mode " + mode + " is not valid for secrets");
        };
    }

    @Override
    public String providerId() {
        return "composite";
    }

    private Optional<String> firstThatSucceeds(SecretKey key) {
        SecretProviderException lastFailure = null;
        for (SecretPort delegate : delegates) {
            try {
                return delegate.lookup(key);
            } catch (SecretProviderException e) {        // failure isolation: try the next provider
                log.warn("Secret provider {} failed, trying the next one", delegate.providerId());
                lastFailure = e;
            }
        }
        throw new SecretProviderException("All secret providers failed", lastFailure);
    }
}
```

```yaml
platform:
  secret:
    mode: failover               # single | broadcast | failover | priority | weighted
    providers: [vault, kubernetes]
```

> **Metrics:** don't write a composite metrics adapter. Micrometer already
> broadcasts to every registry through `CompositeMeterRegistry` (Boot creates one
> when several registries are on the classpath), so add the backend's registry
> dependency instead.

Composition rules:

- The composite is **just another adapter** behind the same port — wired by the
  same `config/x` auto-configuration when `mode != single`.
- **Failure isolation:** in `broadcast`/`failover`, one provider failing must
  not fail the others. Wrap each delegate call in its own try/catch (as in
  `firstThatSucceeds` above) and emit a metric + log on failure (see
  `observability`, `resilience-patterns`).
- A mode that makes no sense for the capability is rejected at startup or on
  first call (as above), never silently treated as another mode.
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

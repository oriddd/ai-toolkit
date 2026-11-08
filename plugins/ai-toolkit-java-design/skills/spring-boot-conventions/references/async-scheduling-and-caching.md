# Spring Boot Conventions Skill — Async work, scheduled jobs and caching

Part of the [`spring-boot-conventions`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 7. Async work — named `TaskExecutor`

Never inject the framework's default `taskExecutor`. Define your own per
purpose so thread pools are sized and observable:

```java
@Configuration
public class TaskExecutorsConfig {
    @Bean("fooAsyncExecutor")
    public ThreadPoolTaskExecutor fooAsyncExecutor() {
        var ex = new ThreadPoolTaskExecutor();
        ex.setCorePoolSize(4);
        ex.setMaxPoolSize(16);
        ex.setQueueCapacity(100);
        ex.setThreadNamePrefix("foo-async-");
        // Pick the rejection policy per use case — CallerRunsPolicy runs the task on the *calling* thread
        // (often an HTTP request thread), which is back-pressure, not async. For request-triggered work prefer
        // AbortPolicy (the default) and map TaskRejectedException to 503 + Retry-After.
        ex.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        ex.setWaitForTasksToCompleteOnShutdown(true);     // drain in-flight work on shutdown
        ex.setAwaitTerminationSeconds(20);                // keep below spring.lifecycle.timeout-per-shutdown-phase
        ex.initialize();
        return ex;
    }
}

@Async("fooAsyncExecutor")
public CompletableFuture<Result> doExpensiveWork(...) { … }
```

Enable with `@EnableAsync` on a `@Configuration` class. Concurrency rules:

- **Always name the executor** in `@Async("…")`. Defining your own `Executor` bean can make Boot back off its
  auto-configured `applicationTaskExecutor` (used by unnamed `@Async` and Spring MVC async), so never rely on the default.
- **Shutdown draining:** a `ThreadPoolTaskExecutor` bean is shut down by Spring; set
  `waitForTasksToCompleteOnShutdown` + `awaitTerminationSeconds` as above. An executor you create yourself (not a
  bean) needs a `@PreDestroy` that calls `shutdown()` → `awaitTermination(…)` → `shutdownNow()` (`graceful-shutdown`).
- **Restore the interrupt flag:** `catch (InterruptedException e) { Thread.currentThread().interrupt(); … }` — never
  swallow it, or shutdown cannot cancel the work.
- **No shared mutable state** between tasks; hand results back through the `CompletableFuture`.
- **Virtual threads (Java 21):** for I/O-bound work, `spring.threads.virtual.enabled=true` (Boot 3.2+) makes the
  auto-configured executors use virtual threads. Keep a bound (semaphore, bulkhead) on calls to a downstream — virtual
  threads remove the pool limit that used to protect it (`resilience-patterns`).

## 7b. Scheduled jobs — `@Scheduled`

Recurring work (cache eviction, throttle reset, retry sweeper, metrics
roll-up) uses `@Scheduled` on a dedicated `*Task` / `*Job` component, never
on a controller or a domain service.

```java
@Slf4j
@Component
@RequiredArgsConstructor
public class ExpiredSessionCleanupTask {

    private final ExpiredSessionStore store;

    @Scheduled(fixedRateString = "${session.cleanup.interval-ms:300000}")
    public void cleanup() {
        try {
            int evicted = store.evictExpired();
            log.info("expired-session-cleanup evicted={}", evicted);
        } catch (Exception e) {
            log.error("expired-session-cleanup failed", e);     // never propagate
        }
    }
}
```

Enabling:

```java
@Configuration
@EnableScheduling
class SchedulingConfig {}
```

— never put `@EnableScheduling` on `@SpringBootApplication`; that couples
the lifecycle of every test slice to the scheduler thread.

Rules:

- **Interval comes from `@ConfigurationProperties`** (or
  `fixedRateString = "${prop:default}"`). Never hard-code milliseconds.
- The task **must complete in `<<` period** under p99 load. If the work is
  unbounded, push it onto a queue and have the task drain N items.
- The task is **idempotent**. If it overlaps itself (slow tick) the second
  run must be a no-op.
- The task **never throws** — always `try/catch`, log and count the failure. (Spring's default error handler logs an uncaught exception and the
  schedule keeps running, so an unhandled failure is easy to miss — it raises no metric or alert on its own.)
- One Micrometer **timer per task** and one counter for failures. On Spring 6.1+ (Boot 3.2+) every `@Scheduled`
  run is already observed as **`tasks.scheduled.execution`** (tagged with the task's class/method and outcome) once
  Boot's observation support is on the classpath — use that as the timer instead of hand-rolling one. Domain
  metrics you add yourself (failure counter, items processed) follow the `request-metrics` naming:
  `<service>.<domain>.<verb>` (e.g. `myservice.sessions.cleanup.failures`), name and tag constants in
  `MonitoringConstants`, never inline strings.
- **Cluster safety:** with `replicas > 1`, plain `@Scheduled` runs on
  every pod. Either accept that (idempotent task) or wrap the body with
  [ShedLock](https://github.com/lukas-krecan/ShedLock) —
  `@SchedulerLock(name = "…", lockAtMostFor = "…")` with `lockAtMostFor` longer than the slowest normal run, so a
  lock held by a pod that died is released. For complex job graphs use Quartz instead.
- On shutdown, in-flight ticks must drain — cross-ref `graceful-shutdown`.

Forbidden:

- `@Scheduled` on a `@RestController` or any class with HTTP handlers.
- `fixedDelay` / `fixedRate` with a numeric literal (`fixedRate = 60000`).
- Catching `Throwable` without logging.
- Sharing mutable state across tick instances.

## 8. Caching

**Default: caching is a pluggable capability.** Domain and application code that needs a cache depends on a
`CachePort` in `spi/` with vendor adapters in `adapter/` (`pluggable-architecture`, guild #20) — that is the
canonical model, and the only one for explicit get/put/evict, shared caches across services, or provider
composition. Do not create a `client.cache` package or call a cache SDK directly.

Spring Cache (`@EnableCaching` + `@Cacheable`) is the accepted **declarative shortcut** — its `CacheManager` is
itself a provider-neutral facade selected by configuration — for read-through memoisation of a single method.
Use it only when:
- the underlying call is **pure** (same input ⇒ same output, modulo TTL);
- the **key** can be expressed declaratively (`@Cacheable(key = "#id")`);
- a **cache name** is unique and documented.

Always pick a concrete provider (Caffeine for in-process, Redis for shared)
— never rely on `ConcurrentMapCacheManager` in production.

```java
@Cacheable(cacheNames = "foo-by-id", key = "#id")
public Foo findById(String id) { … }
```

- **Every cache has a TTL** (guild #9), set per cache name — never one global spec that silently applies to new
  caches. Wire it in one `config/CachingConfig` (which also carries `@EnableCaching`), with the TTLs in a
  properties record:

```java
@ConfigurationProperties(prefix = ConfigurationConstants.CACHE_PREFIX)   // "foo.cache"
public record CacheTtlProperties(@NotEmpty Map<String, Duration> ttl) {}  // foo.cache.ttl.foo-by-id: 10m

@Configuration
@EnableCaching
@RequiredArgsConstructor
class CachingConfig {
    private final CacheTtlProperties props;

    @Bean   // Caffeine (in-process): one custom cache per name, each with its own TTL
    CacheManager cacheManager() {
        var manager = new CaffeineCacheManager();
        // a cache name missing from foo.cache.ttl would still be created on demand, without a TTL — list every name
        props.ttl().forEach((name, ttl) ->
                manager.registerCustomCache(name, Caffeine.newBuilder().expireAfterWrite(ttl).build()));
        return manager;
    }
    // Redis (shared): a RedisCacheManagerBuilderCustomizer calling
    // builder.withCacheConfiguration(name, RedisCacheConfiguration.defaultCacheConfig().entryTtl(ttl)) per entry.
}
```

- **Self-invocation bypasses the cache.** `@Cacheable` works through a Spring proxy, so calling the annotated method
  from another method of the same class (`this.findById(id)`) never hits the cache. Put the cached method on a
  separate bean.

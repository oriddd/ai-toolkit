---
name: rate-limiting
description: >
  Java / Spring Boot: Protect the service from abuse and ensure fair usage using rate-limiting strategies. Covers client-side rate limiting (token bucket), server-side enforcement (Bucket4j, Resilience4j), and distributed rate limiting with Redis. Use when an endpoint or client call must be throttled.
tier: should
applies_to: [rest, monolith]
depends_on: [observability, external-client, pluggable-architecture]
ships_templates: false
hitl: false
version: 1.1
last_reviewed: 2026-11-15
---

# Rate Limiting Skill

Rate limiting prevents a single client from overwhelming the service, whether intentional (DoS attack) or accidental (leaky script).

## 1. Strategies

- **Fixed Window**: 100 requests per minute. Reset at the start of each minute.
- **Sliding Window**: 100 requests in the last 60 seconds (smoother).
- **Token Bucket**: Allows for "bursts". 10 tokens available, regrow 1 token per second.

## 2. Server-Side Enforcement

Limits can be enforced locally or across a cluster.

### 2a. In-process (Local) - Resilience4j
Suitable for **outbound / self-protection**: capping how fast *this instance* calls a downstream or runs an
expensive method. A Resilience4j `RateLimiter` instance is one shared limit per pod — **not** per client — and it
limits calls per period, not concurrency (use a bulkhead for that, `resilience-patterns`). For per-client limits
on inbound requests use Bucket4j (§2b, §3).

Merge under the single top-level `resilience4j:` key of `application.yaml` (resilience, rate-limiting and client skills all add instances to it):

```yaml
resilience4j:
  ratelimiter:
    instances:
      search-api:
        limitForPeriod: 50
        limitRefreshPeriod: 1s
        timeoutDuration: 0
```

```java
@RateLimiter(name = "search-api", fallbackMethod = "throttled")
public SearchResult search(final String query) throws TooManyRequestsException { … }

private SearchResult throttled(final String query, final RequestNotPermitted e) throws TooManyRequestsException {
    throw ExceptionMessages.rateLimitExceeded(1);   // wait ≈ limitRefreshPeriod, in seconds
}
```

The aspect needs `resilience4j-spring-boot3` + `spring-boot-starter-aop` (`resilience-patterns`). The fallback keeps the checked
domain exception: the caller sees `TooManyRequestsException` (429 + `Retry-After`) instead of the library's unchecked
`RequestNotPermitted`. With `timeoutDuration: 0` the third call inside the period is refused at once and the
next period admits calls again.

### 2b. Local Rate Limiting with Bucket4j

```xml
<!-- Bucket4j is not managed by the Spring Boot BOM: pin the version (8.22.0 verified on Boot 3.5) -->
<properties><bucket4j.version>8.22.0</bucket4j.version></properties>

<dependency>
    <groupId>com.bucket4j</groupId>
    <artifactId>bucket4j_jdk17-core</artifactId>
    <version>${bucket4j.version}</version>
</dependency>
```

Behind a port (`pluggable-architecture`, guild #20), so local and Redis buckets are swappable by configuration:

```java
// spi/ratelimit/RateLimiterPort.java — vendor-free
public interface RateLimiterPort {
    RateLimitDecision tryConsume(String clientKey);
}
public record RateLimitDecision(boolean allowed, long retryAfterSeconds) {}
```

The local adapter (`adapter/ratelimit/bucket4j/`) holds the per-client buckets:

```java
// one bucket PER CLIENT (a single shared bucket would let one caller starve everyone) — key it by client id / api key
// bounded (Caffeine): an unbounded map grows with every client id ever seen; idle clients' buckets are evicted
private final Cache<String, Bucket> buckets = Caffeine.newBuilder()
    .expireAfterAccess(Duration.ofMinutes(10))   // longer than the refill window, so an evicted bucket would have been full anyway
    .maximumSize(100_000)
    .build();

Bucket bucket = buckets.get(clientId, id -> Bucket.builder()
    .addLimit(limit -> limit.capacity(10).refillIntervally(10, Duration.ofMinutes(1)))   // Bandwidth.classic / Refill are deprecated in Bucket4j 8.x
    .build());

ConsumptionProbe probe = bucket.tryConsumeAndReturnRemaining(1);
return new RateLimitDecision(probe.isConsumed(),
        TimeUnit.NANOSECONDS.toSeconds(probe.getNanosToWaitForRefill()) + 1);
```

The caller — the operation, or a `HandlerInterceptor` for a per-route limit — turns a refusal into the domain
exception. Both run inside the `DispatcherServlet`, so the `@RestControllerAdvice` answers 429 + `Retry-After`. The operation declares
`throws TooManyRequestsException`; `HandlerInterceptor.preHandle` already declares `throws Exception`:

```java
RateLimitDecision decision = rateLimiter.tryConsume(clientKey);
if (!decision.allowed()) {
    // TooManyRequestsException carries the computed wait; the exception-handling GlobalExceptionHandler template
    // answers 429 with Retry-After = retryAfterSeconds (its 30 s default applies only when no wait is known)
    throw ExceptionMessages.rateLimitExceeded(decision.retryAfterSeconds());
}
```
**Never throw it from a servlet `Filter`.** A filter runs before the `DispatcherServlet`; the advice never sees the
exception and the client gets Boot's `500` error page without `Retry-After`. If the limit must sit in a filter (e.g.
ahead of authentication), hand the exception to the advice instead of throwing it:

```java
// injected: @Qualifier("handlerExceptionResolver") HandlerExceptionResolver resolver
if (!decision.allowed()) {
    resolver.resolveException(request, response, null, ExceptionMessages.rateLimitExceeded(decision.retryAfterSeconds()));
    return;                                       // do not call chain.doFilter
}
chain.doFilter(request, response);
```

In-memory buckets are per instance; use the distributed variant below when the limit must hold across pods.

## 3. Distributed Rate Limiting (Multi-Node)

When running multiple instances, use **Redis + Bucket4j** to have a shared counter. This prevents a client from getting N times the limit by hitting N different pods.

Add a second `RateLimiterPort` adapter (`adapter/ratelimit/redis/`) selected by
`platform.ratelimit.provider: redis`. It uses `com.bucket4j:bucket4j_jdk17-lettuce` (`${bucket4j.version}`, the same release as core) and a
Lettuce-based `ProxyManager` (`LettuceBasedProxyManager`): `proxyManager.getProxy(clientKey, () -> configuration)`
returns a bucket whose state lives in Redis, with an expiration strategy so idle keys are removed. The Lettuce
module does **not** pull Lettuce in: add `io.lettuce:lettuce-core` (managed by the Spring Boot BOM, or use
`spring-boot-starter-data-redis`). Verified on Bucket4j 8.22.0 against Redis 7:

```java
public class RedisBucket4jRateLimiter implements RateLimiterPort {
    private static final BucketConfiguration CONFIGURATION = BucketConfiguration.builder()
            .addLimit(limit -> limit.capacity(10).refillIntervally(10, Duration.ofMinutes(1)))
            .build();
    private final LettuceBasedProxyManager<byte[]> proxyManager;

    public RedisBucket4jRateLimiter(final RedisClient client) {
        final StatefulRedisConnection<byte[], byte[]> connection = client.connect(ByteArrayCodec.INSTANCE);
        this.proxyManager = LettuceBasedProxyManager.builderFor(connection)
                .withExpirationStrategy(
                        ExpirationAfterWriteStrategy.basedOnTimeForRefillingBucketUpToMax(Duration.ofMinutes(2)))
                .build();
    }

    @Override
    public RateLimitDecision tryConsume(final String clientKey) {
        final ConsumptionProbe probe = proxyManager.builder()
                .build(clientKey.getBytes(UTF_8), () -> CONFIGURATION)
                .tryConsumeAndReturnRemaining(1);
        return new RateLimitDecision(probe.isConsumed(),
                TimeUnit.NANOSECONDS.toSeconds(probe.getNanosToWaitForRefill()) + 1);
    }
}
```

Imports: `io.github.bucket4j.redis.lettuce.cas.LettuceBasedProxyManager`, `io.github.bucket4j.distributed.ExpirationAfterWriteStrategy`,
`io.lettuce.core.RedisClient`, `io.lettuce.core.api.StatefulRedisConnection`, `io.lettuce.core.codec.ByteArrayCodec`. Two
adapter instances on two `RedisClient`s (two pods) share one bucket: 20 calls split across them admit exactly 10.
Prove both adapters with one `RateLimiterPort` contract suite (`adapter-contract-tests`); the Redis one runs against a
Testcontainers `redis:7-alpine`.

## 4. Where to Limit?

- **Gateway Layer**: Best for broad protection (IP-based).
- **Controller/Filter**: Best for business-aware limits (User-ID based).

**Choosing the key.** Prefer the authenticated principal (`sub`) or API key. Use the client IP only when there is
no identity, and only as resolved by a **trusted** proxy chain: behind an ingress every request shows the proxy's
IP, and a raw `X-Forwarded-For` is attacker-controlled (rotate it → a fresh bucket per request). Configure
`server.forward-headers-strategy=framework` (or `native`) and let your ingress overwrite, not append, the header —
then read `request.getRemoteAddr()`, never the header yourself.
- **Client Layer**: Best for protecting your own downstream dependencies (see external-client).

## 5. Response Protocol

When a limit is reached:
- Return **`429 Too Many Requests`**.
- Include the **`Retry-After`** header (seconds or timestamp).

## Do / Don't

✅ Start with conservative limits and tune based on metrics.
✅ Use appropriate keys for limiting (e.g., API Key, User ID, or IP).
✅ Return a 429 response with a clear message.
❌ Never use local rate limiting if global consistency is required (use Redis).
❌ Never apply a global rate limit to internal health-check endpoints.
❌ Never use rate limiting as a substitute for optimizing slow code.

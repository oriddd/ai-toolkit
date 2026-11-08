---
name: rate-limiting
description: >
  Java / Spring Boot: Protect the service from abuse and ensure fair usage using rate-limiting strategies. Covers client-side rate limiting (token bucket), server-side enforcement (Bucket4j, Resilience4j), and distributed rate limiting with Redis. Use when an endpoint or client call must be throttled.
tier: should
applies_to: [rest, monolith]
depends_on: [observability, external-client, pluggable-architecture]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
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

```yaml
resilience4j:
  ratelimiter:
    instances:
      search-api:
        limitForPeriod: 50
        limitRefreshPeriod: 1s
        timeoutDuration: 0
```

### 2b. Local Rate Limiting with Bucket4j

```xml
<!-- Bucket4j is not managed by the Spring Boot BOM: pin the version -->
<dependency>
    <groupId>com.bucket4j</groupId>
    <artifactId>bucket4j_jdk17-core</artifactId>
    <version><current></version>
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

The caller (a filter or the operation) turns a refusal into the domain exception:

```java
RateLimitDecision decision = rateLimiter.tryConsume(clientKey);
if (!decision.allowed()) {
    // TooManyRequestsException → 429 + Retry-After, mapped by the exception-handling GlobalExceptionHandler template
    throw ExceptionMessages.rateLimitExceeded(decision.retryAfterSeconds());
}
```
In-memory buckets are per instance; use the distributed variant below when the limit must hold across pods.

## 3. Distributed Rate Limiting (Multi-Node)

When running multiple instances, use **Redis + Bucket4j** to have a shared counter. This prevents a client from getting N times the limit by hitting N different pods.

Add a second `RateLimiterPort` adapter (`adapter/ratelimit/redis/`) selected by
`platform.ratelimit.provider: redis`. It uses `com.bucket4j:bucket4j_jdk17-lettuce` (version `<current>`) and a
Lettuce-based `ProxyManager` (`LettuceBasedProxyManager`): `proxyManager.getProxy(clientKey, () -> configuration)`
returns a bucket whose state lives in Redis, with an expiration strategy so idle keys are removed. Check the
builder API of the Bucket4j version you pin — it changed across 8.x releases. Prove both adapters with one
`RateLimiterPort` contract suite (`adapter-contract-tests`).

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

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
Suitable for fixed-size clusters or simple concurrency protection.

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

if (bucket.tryConsume(1)) {
    return executeRequest();
} else {
    throw new TooManyRequestsException();   // map it to 429 + Retry-After in your @RestControllerAdvice — no shipped template does
}
```
In-memory buckets are per instance; use the distributed variant below when the limit must hold across pods.

## 3. Distributed Rate Limiting (Multi-Node)

When running multiple instances, use **Redis + Bucket4j** to have a shared counter. This prevents a client from getting N times the limit by hitting N different pods.

## 4. Where to Limit?

- **Gateway Layer**: Best for broad protection (IP-based).
- **Controller/Filter**: Best for business-aware limits (User-ID based).
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

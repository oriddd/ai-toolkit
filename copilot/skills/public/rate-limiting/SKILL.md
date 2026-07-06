---
name: rate-limiting
description: Protect the service from abuse and ensure fair usage using rate-limiting strategies. Covers client-side rate limiting (token bucket), server-side enforcement (Bucket4j, Resilience4j), and distributed rate limiting with Redis.
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
Bucket bucket = Bucket.builder()
    .addLimit(Bandwidth.classic(10, Refill.intervally(10, Duration.ofMinutes(1))))
    .build();

if (bucket.tryConsume(1)) {
    return executeRequest();
} else {
    throw new TooManyRequestsException();
}
```

## 3. Distributed Rate Limiting (Multi-Node)

When running multiple instances, use **Redis + Bucket4j** to have a shared counter. This prevents a client from getting N times the limit by hitting N different pods.

## 4. Where to Limit?

- **Gateway Layer**: Best for broad protection (IP-based).
- **Controller/Filter**: Best for business-aware limits (User-ID based).
- **Client Layer**: Best for protecting your own downstream dependencies (see [external-client](../external-client/SKILL.md)).

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

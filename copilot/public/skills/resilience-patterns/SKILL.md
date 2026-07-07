---
name: resilience-patterns
description: Beyond simple retries — implement advanced stability patterns using Resilience4j (Bulkheads, Timeouts, Rate Limiters) and architectural strategies (Fallback, Sidecar, Fail-fast) to protect the service from cascading failures in a distributed system.
tier: must
applies_to: [rest, event, monolith]
depends_on: [external-client]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Resilience Patterns Skill

This skill extends the `external-client` resilience section to provide a comprehensive stability toolkit.

## 1. The Bulkhead Pattern

Prevent a failure in one part of the system from taking down the entire service by isolating resources.

- **Thread Pool Bulkhead**: Separate thread pools for different external dependencies.
- **Semaphore Bulkhead**: Limit the number of concurrent calls to a dependency.

```yaml
resilience4j:
  bulkhead:
    instances:
      dependency-a:
        maxConcurrentCalls: 10
        maxWaitDuration: 0
```

### 1b. Adaptive Bulkhead
For dynamic environments, consider **Concurrency Limits** (e.g., Netflix's `concurrency-limits` or Resilience4j's adaptive bulkhead) which adjust the limit based on observed latency rather than static configuration.

## 2. Circuit Breaker
Protects the system by failing fast when a dependency is unstable.

```yaml
resilience4j:
  circuitbreaker:
    instances:
      dependency-a:
        slidingWindowSize: 100
        permittedNumberOfCallsInHalfOpenState: 10
        waitDurationInOpenState: 10s
        failureRateThreshold: 50
        eventConsumerBufferSize: 10
```

- **OPEN**: Requests fail immediately with `CallNotPermittedException`.
- **HALF_OPEN**: A limited number of probe requests are allowed through to see if the dependency has recovered.
- **CLOSED**: Normal operation.

## 3. Timeouts

Every network call **must** have a timeout.
- **Connect Timeout**: Max time to establish a TCP connection.
- **Read Timeout**: Max time to wait for a packet.
- **Request Timeout**: Total time for the operation (enforced by Resilience4j/Spring).

## 4. The Fail-Fast Pattern

If a dependency is known to be down (Circuit Breaker is OPEN), fail the request immediately without attempting the call. This preserves your service's own threads and resources.

## 5. Fallback Strategies

When a call fails or is rejected by a bulkhead/circuit-breaker, provide a safe alternative:
- **Cached Value**: Return the last known good value from a cache.
- **Static Default**: Return a safe "empty" or "default" state.
- **Stubbed Response**: Return a hardcoded response (only if appropriate for the domain).
- **Error Propagation**: Translate to a meaningful domain exception (e.g., `503 Service Unavailable`).

## 6. Observability
Every resilience event (circuit breaker opening, bulkhead rejection) must emit a **Metric** and a **Log entry** (see [observability](../observability/SKILL.md)). Resilience4j provides an `EventPublisher` for this:

```java
registry.circuitBreaker("my-cb").getEventPublisher()
    .onStateTransition(event -> log.warn("Circuit Breaker transitioned: {}", event.getStateTransition()));
```

## 7. Idempotency Keys

For any write operation (`POST`, `PUT`, `DELETE`), use an idempotency key to make retries safe.
- Client passes `X-Idempotency-Key`.
- Server records the result of the first call and returns it for subsequent calls with the same key.

## Do / Don't

✅ Apply Bulkheads to protect your service's thread pool.
✅ Use Timeouts that are shorter than the caller's timeout.
✅ Implement Circuit Breakers for all external IO.
✅ Prefer Fail-Fast over long-running retries during outages.
❌ Never use infinite retries.
❌ Never share thread pools between a high-traffic endpoint and a slow internal dependency.
❌ Never hide failures with "silent" fallbacks that lead to data inconsistency.

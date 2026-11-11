---
name: resilience-patterns
description: >
  Java / Spring Boot stability with Resilience4j — timeouts, bulkheads, circuit breakers, fallbacks, fail-fast. Use
  when a downstream call needs protection from slow or failing dependencies or cascading failures. For rate limiting
  use `rate-limiting`.
tier: must
applies_to: [rest, event, monolith]
depends_on: [external-client]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-11
---

# Resilience Patterns Skill

This skill extends the `external-client` resilience section to provide a comprehensive stability toolkit.

Resilience4j annotations (`@CircuitBreaker`, `@Retry`, `@Bulkhead`, `@TimeLimiter`, `@RateLimiter`) are aspects:
they need `resilience4j-spring-boot3` **and** `spring-boot-starter-aop` on the classpath, with versions from
`resilience4j-bom` (`external-client` §10). Without the AOP starter they are silently ignored.
`resilience4j-micrometer` publishes `resilience4j_*` metrics for every instance automatically once Actuator +
Micrometer are present.

> **Boot 4 note:** the AOP starter is `spring-boot-starter-aspectj`; check the Resilience4j starter name for
> Boot 4 before upgrading. Spring Framework 7 also ships native `@Retryable` and `@ConcurrencyLimit` in core —
> pick one mechanism per service.

## 1. The Bulkhead Pattern

Prevent a failure in one part of the system from taking down the entire service by isolating resources.

- **Thread Pool Bulkhead**: Separate thread pools for different external dependencies. **Async only:** the
  annotation works only on methods returning `CompletionStage` / `CompletableFuture`; on a synchronous method every
  call fails with `IllegalStateException: ThreadPool bulkhead is only applicable for completable futures` (at call
  time, not at startup — the context starts fine and the first request breaks).
- **Semaphore Bulkhead**: Limit the number of concurrent calls to a dependency. Works on synchronous methods —
  the default choice for blocking (servlet) code.

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
- **Request Timeout**: Total time for the operation (enforced by Resilience4j/Spring). Resilience4j
  `@TimeLimiter` works **only on async return types** (`CompletionStage` / `CompletableFuture`); on a synchronous
  method every call throws `IllegalReturnTypeException` ("CompletionStage expected") — at call time, not at startup. For synchronous code, set connect and read timeouts on the HTTP client
  itself (`external-client` §6) and bound retries with a total time budget (`external-client` §10).

## 4. The Fail-Fast Pattern

If a dependency is known to be down (Circuit Breaker is OPEN), fail the request immediately without attempting the call. This preserves your service's own threads and resources.

## 5. Fallback Strategies

When a call fails or is rejected by a bulkhead/circuit-breaker, provide a safe alternative:
> These value-returning fallbacks are only for **non-critical, read-only enrichment**. A transport in an `external-client` package never returns a
> silent default: its fallback throws a domain exception so the outage is visible (`external-client` Do / Don't).

- **Cached Value**: Return the last known good value from a cache.
- **Static Default**: Return a safe "empty" or "default" state.
- **Stubbed Response**: Return a hardcoded response (only if appropriate for the domain).
- **Error Propagation**: Translate to a meaningful domain exception (e.g., `503 Service Unavailable`).

## 6. Observability
Every resilience event (circuit breaker opening, bulkhead rejection) must emit a **Metric** and a **Log entry** (see observability). Resilience4j provides an `EventPublisher` for this:

```java
// find(): a typo fails fast — circuitBreaker(name) would silently create a new, unconfigured breaker
registry.find("my-cb")
    .orElseThrow(() -> new IllegalStateException("No circuit breaker named my-cb"))
    .getEventPublisher()
    .onStateTransition(event -> log.warn("Circuit Breaker transitioned: {}", event.getStateTransition()));
```

Metrics need no code: `resilience4j-micrometer` (pulled in by the starter) registers them per instance.

## 7. Idempotency Keys

For any non-idempotent write (`POST`, `PATCH`; `PUT` and `DELETE` are idempotent by definition), use an
idempotency key to make retries safe — the contract is `spring-boot-conventions` §9 / `api-design`.
- Client passes `Idempotency-Key` (IETF draft name; no `X-` prefix).
- Server records the result of the first call and returns it for subsequent calls with the same key.

## Do / Don't

✅ Apply Bulkheads to protect your service's thread pool.
✅ Use Timeouts that are shorter than the caller's timeout.
✅ Implement Circuit Breakers for all external IO.
✅ Prefer Fail-Fast over long-running retries during outages.
❌ Never use infinite retries.
❌ Never share thread pools between a high-traffic endpoint and a slow internal dependency.
❌ Never hide failures with "silent" fallbacks that lead to data inconsistency.

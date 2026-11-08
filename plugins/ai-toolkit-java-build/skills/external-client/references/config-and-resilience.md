# External Client — Spring properties and Resilience4j (§9–§10)

Part of the [`external-client`](../SKILL.md) skill. Section numbers are stable; other skills cite them.

## 9. Spring properties

```yaml
foo-service:
  base-url: http://${FOO_HOST:localhost}:${FOO_PORT:8080}
  search-endpoint: /api/v1/search
  timeouts:
    connect: 1s
    read: 2s            # per attempt; keep (read × maxAttempts + waits) below the caller's SLA
```

Bind the block with one `FooProperties` `@ConfigurationProperties` record
(`spring-boot-conventions` §1; shown in §6) — never `@Value`. Mirror every key as a constant in
`constant/ConfigurationConstants` (one constant per prefix, used by
`@ConfigurationProperties`; `spring-boot-conventions` §1). Add liveness/readiness probes for this dependency (see
`health-indicator`).

## 10. Resilience — Resilience4j

```xml
<!-- dependencyManagement: Resilience4j is not in the Spring Boot BOM -->
<dependency>
    <groupId>io.github.resilience4j</groupId>
    <artifactId>resilience4j-bom</artifactId>
    <version><current></version>
    <type>pom</type>
    <scope>import</scope>
</dependency>

<!-- dependencies -->
<dependency>
    <groupId>io.github.resilience4j</groupId>
    <artifactId>resilience4j-spring-boot3</artifactId>
</dependency>
<!-- REQUIRED: @CircuitBreaker / @Retry are aspects; without AOP they are silently ignored -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-aop</artifactId>
</dependency>
```

> **Boot 4 note:** the AOP starter is named `spring-boot-starter-aspectj` there.

```yaml
resilience4j:
  circuitbreaker.instances.foo-service:
    failureRateThreshold: 50
    slowCallDurationThreshold: 1s           # below the 2s read timeout, so slowness opens the circuit before timeouts pile up
    slidingWindowSize: 20
  retry.instances.foo-service:
    maxAttempts: 3
    waitDuration: 200ms
    enableExponentialBackoff: true          # without this the multiplier below is ignored
    exponentialBackoffMultiplier: 2
    retryExceptions:
      # the exception FooClient translates a transient failure (5xx, timeout) into (§6) — Retry never sees the raw
      # WebClientResponseException because handleResponse() has already wrapped it.
      # {{basePackage}}.exception.UnavailableException (exception-handling), e.g.:
      - com.example.foo.exception.UnavailableException
```

```java
@CircuitBreaker(name = "foo-service", fallbackMethod = "fallback")
@Retry(name = "foo-service")
public FooSearchResponseDto search(final FooSearchRequestDto request) { … }   // unchecked domain exceptions: no throws

private FooSearchResponseDto fallback(final FooSearchRequestDto req, final Throwable t) {
    if (t instanceof BaseDomainException mapped) {
        throw mapped;               // keep the type: UnavailableException stays retryable, DependencyException does not
    }
    // e.g. CallNotPermittedException (circuit open) → 503 + Retry-After
    throw ExceptionMessages.dependencyUnavailable("foo-service", t);
}
```

Rules:
- Aspect order is Retry → CircuitBreaker → …, so Retry sees what the circuit-breaker fallback throws. The fallback
  therefore **rethrows** a mapped domain exception unchanged: wrapping everything into one type would hide
  `UnavailableException` from `retryExceptions`, and Retry would never fire. A non-retryable error
  (`DependencyException`) must stay a different domain exception.
- Test it: two 503s then a 200 → the client is called **3 times** and succeeds; a 400 → called **once**.
- **Bound the total time**: per-attempt read timeout × `maxAttempts` + waits must stay below the caller's SLA
  (2s × 3 + 0.2s + 0.4s ≈ 6.6s here). Tighten the read timeout before adding attempts.
- Retry only **idempotent** operations (`GET`, count-only `POST`). Never retry
  state-mutating operations unless the producer supports idempotency keys.
- The fallback method **always** throws a domain exception — never returns a
  silent empty/null that masks the outage.
- Tune thresholds per dependency; never copy defaults.

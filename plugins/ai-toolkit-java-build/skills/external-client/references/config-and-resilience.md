# External Client — Spring properties and Resilience4j (§9–§10)

Part of the [`external-client`](../SKILL.md) skill. Section numbers are stable; other skills cite them.

## 9. Spring properties

```yaml
foo-service:
  base-url: http://${FOO_HOST:localhost}:${FOO_PORT:8080}
  search-endpoint: /api/v1/search
  timeouts:
    connect-ms: 5000
    read-ms: 30000
```

Mirror every key as a constant in `ConfigurationConstants` (see
`spring-boot-conventions` §1). Add liveness/readiness probes for this
dependency (see `health-indicator`).

## 10. Resilience — Resilience4j

```xml
<dependency>
    <groupId>io.github.resilience4j</groupId>
    <artifactId>resilience4j-spring-boot3</artifactId>
</dependency>
```

```yaml
resilience4j:
  circuitbreaker.instances.foo-service:
    failureRateThreshold: 50
    slowCallDurationThreshold: 2s
    slidingWindowSize: 20
  retry.instances.foo-service:
    maxAttempts: 3
    waitDuration: 200ms
    exponentialBackoffMultiplier: 2
    retryExceptions:
      - org.springframework.web.reactive.function.client.WebClientResponseException$ServiceUnavailable
```

```java
@CircuitBreaker(name = "foo-service", fallbackMethod = "fallback")
@Retry(name = "foo-service")
public FooSearchResponseDto search(final FooSearchRequestDto request) { … }

private FooSearchResponseDto fallback(final FooSearchRequestDto req, final Throwable t) {
    throw new FooException(ExceptionMessages.FOO_SERVICE_UNAVAILABLE, t);
}
```

Rules:
- Retry only **idempotent** operations (`GET`, count-only `POST`). Never retry
  state-mutating operations unless the producer supports idempotency keys.
- The fallback method **always** throws a domain exception — never returns a
  silent empty/null that masks the outage.
- Tune thresholds per dependency; never copy defaults.

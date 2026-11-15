# Exception Handling Skill — minimal advice

Part of the [`exception-handling`](../SKILL.md) skill.

## 3. `@RestControllerAdvice` (vanilla Spring Boot 3)

The shipped `GlobalExceptionHandler.java.tmpl` is the full version (validation, retry-after, optimistic locking); this is its core.

```java
@RestControllerAdvice
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    @ExceptionHandler(BadRequestException.class)
    public ProblemDetail onBadRequest(final BadRequestException e) {
        return build(HttpStatus.BAD_REQUEST, e);
    }

    @ExceptionHandler(ForbiddenException.class)
    public ProblemDetail onForbidden(final ForbiddenException e) {
        return build(HttpStatus.FORBIDDEN, e);
    }

    @ExceptionHandler(NotFoundException.class)
    public ProblemDetail onNotFound(final NotFoundException e) {
        return build(HttpStatus.NOT_FOUND, e);
    }

    @ExceptionHandler(UnavailableException.class)          // 503 + Retry-After (the exception's retryAfter, else 30 s)
    public ResponseEntity<ProblemDetail> onUnavailable(final UnavailableException e) {
        final String seconds = String.valueOf(e.getRetryAfter().map(Duration::toSeconds).orElse(30L));
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .header(HttpHeaders.RETRY_AFTER, seconds)
                .body(build(HttpStatus.SERVICE_UNAVAILABLE, e));
    }

    @ExceptionHandler(BaseDomainException.class)
    public ProblemDetail onDomain(final BaseDomainException e) {
        return build(HttpStatus.INTERNAL_SERVER_ERROR, e);
    }

    @ExceptionHandler(Exception.class)                     // catch-all for bugs
    public ProblemDetail onUnexpected(final Exception e) throws Exception {
        if (e instanceof AccessDeniedException || e instanceof AuthenticationException) {
            throw e;                                       // let Spring Security answer 401 / 403
        }
        log.error("Unhandled exception", e);
        return ProblemDetail.forStatusAndDetail(HttpStatus.INTERNAL_SERVER_ERROR, "Internal server error");
    }

    private ProblemDetail build(final HttpStatus status, final BaseDomainException e) {
        final boolean hideDetail = status.is5xxServerError() && status != HttpStatus.SERVICE_UNAVAILABLE;
        if (hideDetail) {
            log.error("Domain failure [{}]", e.getErrorCode(), e);   // cause is logged, never returned
        }
        final ProblemDetail pd = ProblemDetail.forStatus(status);
        pd.setTitle(status.getReasonPhrase());
        pd.setDetail(hideDetail ? "Internal server error" : e.getMessage());
        pd.setProperty("errorCode", e.getErrorCode());
        pd.setProperty("timestamp", Instant.now().toString());
        return pd;
    }
}
```

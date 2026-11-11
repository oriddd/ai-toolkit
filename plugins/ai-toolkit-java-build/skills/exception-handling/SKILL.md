---
name: exception-handling
description: >
  Java / Spring Boot error contract — typed domain exception hierarchy, static ExceptionMessages catalogue,
  @RestControllerAdvice mapping each exception to an RFC 9457 ProblemDetail. Use when throwing, adding or mapping any
  exception or error response; never throw a raw RuntimeException.
tier: must
applies_to: [rest, event, monolith]
depends_on: [code-structure]
ships_templates: true
hitl: false
version: 1.0
last_reviewed: 2026-11-11
---

# Exception Handling Skill
This skill enforces a project-wide error contract:

- Internal code throws **domain exceptions** — typed subclasses of the unchecked
  `BaseDomainException`, never a raw `RuntimeException`.
- A single `@RestControllerAdvice` translates every exception (domain or
  third-party) into an [RFC 9457 `ProblemDetail`](https://www.rfc-editor.org/rfc/rfc9457)
  with a stable HTTP status.
- All user-facing messages live in `exception/constants/ExceptionMessages`
  and are formatted with `java.text.MessageFormat` — never inlined.

The skill uses **only stock Spring Boot 3 primitives**:
`org.springframework.http.ProblemDetail`,
`org.springframework.web.bind.annotation.RestControllerAdvice`,
`org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler`.

> **Your own bases** (e.g. your own `ResponseEntityExceptionHandler`
> super-class that adds `traceId`, request URI, shared error codes)
> are layered on top via a wrapper in your codebase.

## Reference layout

```
exception/
├── BaseDomainException.java              # base – unchecked (extends RuntimeException), carries errorCode
├── BadRequestException.java              # extends base – maps to 400
├── ForbiddenException.java               # extends base – maps to 403
├── NotFoundException.java                # extends base – maps to 404
├── ConflictException.java                # extends base – maps to 409
├── UnsupportedApiVersionException.java   # extends base – maps to 406 (response-mapper)
├── DependencyException.java              # extends base – maps to 500 (downstream non-2xx that is not an outage)
├── TooManyRequestsException.java         # extends base – maps to 429 + Retry-After
├── UnavailableException.java             # extends base – maps to 503 + Retry-After (downstream down)
├── constants/
│   └── ExceptionMessages.java            # error codes + MessageFormat templates + factory methods
└── handler/
    └── GlobalExceptionHandler.java       # @RestControllerAdvice extends ResponseEntityExceptionHandler
```

These names and packages are the **single source** for every other skill
(permissions, persistence, messaging, external-client, input-validation,
rate-limiting …): import `{{basePackage}}.exception.*` and
`{{basePackage}}.exception.constants.ExceptionMessages`; never define a
parallel hierarchy (e.g. a `CacheClientException extends RuntimeException`).
If you prefer a domain prefix (`FooNotFoundException`), apply it to the
whole hierarchy consistently.

## Inputs

| # | Question | Default |
| - | -------- | ------- |
| 1 | Domain prefix for the exceptions (e.g. `Foo` → `FooNotFoundException`)? | none (`BaseDomainException`, `NotFoundException`, …) |
| 2 | Which HTTP statuses must be mapped? | `400`, `403`, `404`, `406`, `409`, `429`, `500`, `503` |
| 3 | Third-party exceptions that must also be mapped (FQCN → status)? | none |

The base exception is always **unchecked**: no `throws` clauses for domain
exceptions, and `@Transactional` rolls back on them by default.

## Generation rules

### 1. Base + subclass exceptions

```java
public abstract class BaseDomainException extends RuntimeException {
    private final String errorCode;
    protected BaseDomainException(String errorCode, String message)                  { super(message); this.errorCode = errorCode; }
    protected BaseDomainException(String errorCode, String message, Throwable cause) { super(message, cause); this.errorCode = errorCode; }
    public String getErrorCode() { return errorCode; }
}

public class BadRequestException extends BaseDomainException {
    public BadRequestException(String errorCode, String message)                  { super(errorCode, message); }
    public BadRequestException(String errorCode, String message, Throwable cause) { super(errorCode, message, cause); }
}
// …Forbidden / NotFound / Conflict / TooManyRequests / Unavailable similarly
```

Rules:
- Always provide both `(errorCode, message)` and `(errorCode, message, cause)` constructors.
- **Never** throw a raw `RuntimeException` for expected error paths — always a
  subclass of `BaseDomainException`, so the advice can map it.
- **Never** add fields other than the `errorCode` taken from
  `ExceptionMessages` — the HTTP status belongs in the advice. The
  exception's identity *is* the mapping. One exception: the two retryable
  types, `TooManyRequestsException` and `UnavailableException`, may carry an
  optional `retryAfter` (`Duration`) that the advice turns into the
  `Retry-After` header — the thrower (a rate limiter, an open circuit
  breaker) is the only one that knows how long to wait. Without it the
  advice sends its default (30 s).

### 2. `ExceptionMessages`

```java
@NoArgsConstructor(access = AccessLevel.PRIVATE)
public final class ExceptionMessages {
    // error codes
    public static final String ERR_BAD_REQUEST         = "ERR-BAD-REQUEST";
    public static final String ERR_NOT_FOUND           = "ERR-NOT-FOUND";
    public static final String ERR_FORBIDDEN           = "ERR-FORBIDDEN";
    public static final String ERR_UNAVAILABLE         = "ERR-UNAVAILABLE";
    // message templates
    public static final String UNRECOGNIZED_INPUT      = "Unrecognized input: {0}";
    public static final String RESOURCE_NOT_FOUND      = "Resource {0} not found";
    public static final String FORBIDDEN_FOR_RESOURCE  = "Caller has no access to resource {0}";
    public static final String DEPENDENCY_UNAVAILABLE  = "Downstream dependency {0} is unavailable";

    // factory methods — the preferred way to build an exception
    public static NotFoundException resourceNotFound(String type, String id) {
        return new NotFoundException(ERR_NOT_FOUND, MessageFormat.format(RESOURCE_NOT_FOUND, type + " " + id));
    }
    public static UnavailableException dependencyUnavailable(String dependency, Throwable cause) {
        return new UnavailableException(ERR_UNAVAILABLE, MessageFormat.format(DEPENDENCY_UNAVAILABLE, dependency), cause);
    }
}
```

The shipped template also has `versionConflict`, `invalidField`,
`accessDenied`, `callerContextNotFound()`, `unrecognizedCallerContext(ctx)`,
`rateLimitExceeded(seconds)`, `dependencyCallFailed(dep, status)` and
`unsupportedApiVersion(supportedVersions)`.

Rules:
- Use `MessageFormat` placeholders `{0}`, `{1}`, … — **never** `String.format`
  (`%s`), so messages translate uniformly.
- One constant per logical message. If the same message is thrown from two
  places it stays one constant.
- The class is `final` with a private constructor (Lombok or hand-written).

Callers use a factory method, or format at the throw site:

```java
throw ExceptionMessages.resourceNotFound("Invoice", invoiceId);
throw new BadRequestException(ExceptionMessages.ERR_BAD_REQUEST,
        MessageFormat.format(ExceptionMessages.UNRECOGNIZED_INPUT, value));
```

### 3. `@RestControllerAdvice` (vanilla Spring Boot 3)

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

Rules:
- **Extend `ResponseEntityExceptionHandler`** so Spring's built-in handlers
  for `MethodArgumentNotValidException`, `HttpMessageNotReadableException`,
  etc. remain wired and produce `ProblemDetail` responses.
- **Validation errors share one 400 shape** (`errorCode` + `errors[{field, message}]`).
  The template overrides `handleMethodArgumentNotValid` (`@Valid @RequestBody`)
  and `handleHandlerMethodValidationException` (constraints on controller
  parameters — Spring 6.1+ built-in method validation, the default because
  controllers carry no class-level `@Validated`, see `input-validation` §2c),
  and handles `ConstraintViolationException` (a `@Validated` bean outside the
  web layer, or a controller implementing an openapi-generator interface — the
  generated interface is `@Validated`). Spring's defaults answer only `"Invalid request content."` /
  `"Validation failure"` with no field or message.
- **Declaration order doesn't matter** — Spring picks the handler whose
  exception type is the closest match (by inheritance depth), so the
  `BaseDomainException` and `Exception` handlers only catch what nothing
  more specific handles.
- **5xx never echoes `e.getMessage()`** — a wrapped downstream failure may
  carry remote details. Log it with the cause and return a generic detail.
  The 503 detail is safe because it is our own catalogue text.
- Map every third-party exception that can escape the boundary here, **not**
  in the service layer. Services rethrow as-is or wrap into a domain exception.
- The `build` helper is the place to add cross-cutting fields (timestamp,
  request URI, traceId, error code). You may use a wrapper
  in your codebase that swaps the super-class for your own base
  ExceptionHandler that already adds those fields.

### 4. Throw-site policy

| Situation | What to throw |
| --- | --- |
| Input is syntactically invalid (bad enum value, missing required param) | Nothing — binding and Bean Validation (`input-validation`) reject it before your code runs; never write `if (x == null) throw` guards |
| Input is well-formed but the business rule rejects it | `BadRequestException` |
| Caller is authenticated but not allowed for this resource | `ForbiddenException` |
| Resource genuinely does not exist | `NotFoundException` |
| State conflict (duplicate, stale version) | `ConflictException` (409) |
| Requested API version / projection is not served | `UnsupportedApiVersionException` (406) |
| Caller exceeded its rate limit | `TooManyRequestsException` (429 + `Retry-After`) |
| Downstream dependency is down / timed out (5xx, timeout, connection refused) | `UnavailableException` wrapping the cause (→ 503 + `Retry-After`) |
| Downstream returned an unexpected error that is not an outage (e.g. a 4xx caused by our request) | `DependencyException` via `ExceptionMessages.dependencyCallFailed(dep, status)` (→ 500, generic detail) |
| Programmer error (precondition violation inside the service) | `IllegalStateException` / `IllegalArgumentException` (not handled by `ResponseEntityExceptionHandler`, which only covers Spring MVC exceptions — they reach the catch-all handler and become a logged `500`, which is right for a bug) |

> **About the shipped templates.** They implement exactly the model above:
> unchecked `BaseDomainException` with an `errorCode`, the
> `ExceptionMessages` catalogue (codes, `MessageFormat` templates, factory
> methods) and one `GlobalExceptionHandler` in `exception/handler/`.

## Reference map — load only the part you are working on

| Sections | Topic | Load when | File |
| --- | --- | --- | --- |
| Tests | slice / standalone tests of the advice, subclass assertions, component-test status matrix | testing the error contract | [`testing.md`](./references/testing.md) |

## Do / Don't

✅ One advice class per microservice; it lives in `exception/handler/`.
✅ Always extend `ResponseEntityExceptionHandler` (or your own base
or your own extension of it) to get framework-provided
handlers for free.
✅ Use `MessageFormat` placeholders so messages are i18n-ready and uniform.
✅ Map third-party exceptions in the **advice**, not by `try/catch + rethrow`
in services.
❌ Never return raw strings or custom error JSON from a controller — use
`ProblemDetail`.
❌ Never throw `RuntimeException` from business code for expected failures —
that defeats the typed advice mapping.
❌ Never inline error messages — add a constant in `ExceptionMessages` and
`MessageFormat` it.
❌ Never put HTTP types (`HttpStatus`, `ResponseEntity`) anywhere except the
controller and the advice.

## 5. Templates

- [`BaseDomainException.java.tmpl`](./templates/BaseDomainException.java.tmpl) — Common base class.
- [`NotFoundException.java.tmpl`](./templates/NotFoundException.java.tmpl) — Maps to 404.
- [`ConflictException.java.tmpl`](./templates/ConflictException.java.tmpl) — Maps to 409.
- [`BadRequestException.java.tmpl`](./templates/BadRequestException.java.tmpl) — Maps to 400.
- [`ForbiddenException.java.tmpl`](./templates/ForbiddenException.java.tmpl) — Maps to 403.
- [`TooManyRequestsException.java.tmpl`](./templates/TooManyRequestsException.java.tmpl) — Maps to 429 + `Retry-After`.
- [`UnavailableException.java.tmpl`](./templates/UnavailableException.java.tmpl) — Maps to 503 + `Retry-After`.
- [`UnsupportedApiVersionException.java.tmpl`](./templates/UnsupportedApiVersionException.java.tmpl) — Maps to 406.
- [`DependencyException.java.tmpl`](./templates/DependencyException.java.tmpl) — Maps to 500 (generic detail).
- [`ExceptionMessages.java.tmpl`](./templates/ExceptionMessages.java.tmpl) — Message catalogue.
- [`GlobalExceptionHandler.java.tmpl`](./templates/GlobalExceptionHandler.java.tmpl) — The `@RestControllerAdvice`.

---
name: exception-handling
description: Wire a clean error contract for a Spring Boot microservice — a typed domain exception hierarchy, a static ExceptionMessages catalogue, and a @RestControllerAdvice that maps each exception to an RFC 7807 ProblemDetail response with the correct HTTP status. Uses only stock Spring Boot (3.x ProblemDetail support). No private libraries required.
tier: must
applies_to: [rest, event, monolith]
depends_on: [code-structure]
ships_templates: true
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Exception Handling Skill (public)

This skill enforces a project-wide error contract:

- Internal code throws **domain exceptions** (typed, not `RuntimeException`).
- A single `@RestControllerAdvice` translates every exception (domain or
  third-party) into an [RFC 7807 `ProblemDetail`](https://www.rfc-editor.org/rfc/rfc7807)
  with a stable HTTP status.
- All user-facing messages live in `exception/constants/ExceptionMessages`
  and are formatted with `java.text.MessageFormat` — never inlined.

The skill uses **only stock Spring Boot 3 primitives**:
`org.springframework.http.ProblemDetail`,
`org.springframework.web.bind.annotation.RestControllerAdvice`,
`org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler`.

> **Organization-specific bases** (e.g. an internal `ResponseEntityExceptionHandler`
> super-class that adds `traceId`, request URI, organization-wide error codes)
> are layered on top via a private wrapper in your fork.

## Reference layout

```
exception/
├── <Domain>Exception.java                # base – checked
├── <Domain>BadRequestException.java      # extends base – maps to 400
├── <Domain>ForbiddenException.java       # extends base – maps to 403
├── <Domain>NotFoundException.java        # extends base – maps to 404
├── constants/
│   └── ExceptionMessages.java            # static final String catalogue, MessageFormat-ready
└── handler/
    └── <Domain>ExceptionsHandler.java    # @RestControllerAdvice extends ResponseEntityExceptionHandler
```

## Inputs

| # | Question | Default |
| - | -------- | ------- |
| 1 | Domain prefix for the exceptions (e.g. `Foo` → `FooException`)? | derived from service name |
| 2 | Should the base exception be **checked** or **unchecked**? | checked |
| 3 | Which HTTP statuses must be mapped? | `400`, `403`, `404`, `500` |
| 4 | Third-party exceptions that must also be mapped (FQCN → status)? | none |

## Generation rules

### 1. Base + subclass exceptions

```java
public class FooException extends Exception {
    public FooException(final String message)                       { super(message); }
    public FooException(final String message, final Throwable cause){ super(message, cause); }
}

public class FooBadRequestException extends FooException {
    public FooBadRequestException(final String m)                       { super(m); }
    public FooBadRequestException(final String m, final Throwable c)    { super(m, c); }
}
// …Forbidden / NotFound similarly
```

Rules:
- Always provide both `(String)` and `(String, Throwable)` constructors.
- **Never** subclass `RuntimeException` for expected error paths — the
  signature lies to callers.
- **Never** add fields (status code, error code, …) — that belongs in the
  advice. The exception's identity *is* the mapping.

### 2. `ExceptionMessages`

```java
@NoArgsConstructor(access = AccessLevel.PRIVATE)
public final class ExceptionMessages {
    public static final String UNRECOGNIZED_INPUT      = "Unrecognized input: {0}";
    public static final String RESOURCE_NOT_FOUND      = "Resource {0} not found";
    public static final String FORBIDDEN_FOR_RESOURCE  = "Caller has no access to resource {0}";
    public static final String DEPENDENCY_UNAVAILABLE  = "Downstream dependency {0} is unavailable";
}
```

Rules:
- Use `MessageFormat` placeholders `{0}`, `{1}`, … — **never** `String.format`
  (`%s`), so messages translate uniformly.
- One constant per logical message. If the same message is thrown from two
  places it stays one constant.
- The class is `final` with a private constructor (Lombok or hand-written).

Callers format at the throw site:

```java
throw new FooBadRequestException(MessageFormat.format(ExceptionMessages.UNRECOGNIZED_INPUT, value));
```

### 3. `@RestControllerAdvice` (vanilla Spring Boot 3)

```java
@RestControllerAdvice
public class FooExceptionsHandler extends ResponseEntityExceptionHandler {

    @ExceptionHandler(FooBadRequestException.class)
    public ProblemDetail handle(final FooBadRequestException e) {
        return build(HttpStatus.BAD_REQUEST, e);
    }

    @ExceptionHandler(FooForbiddenException.class)
    public ProblemDetail handle(final FooForbiddenException e) {
        return build(HttpStatus.FORBIDDEN, e);
    }

    @ExceptionHandler(FooNotFoundException.class)
    public ProblemDetail handle(final FooNotFoundException e) {
        return build(HttpStatus.NOT_FOUND, e);
    }

    @ExceptionHandler(FooException.class)
    public ProblemDetail handle(final FooException e) {
        return build(HttpStatus.INTERNAL_SERVER_ERROR, e);
    }

    private ProblemDetail build(final HttpStatus status, final Exception e) {
        final ProblemDetail pd = ProblemDetail.forStatus(status);
        pd.setTitle(status.getReasonPhrase());
        pd.setDetail(e.getMessage());
        pd.setProperty("timestamp", Instant.now().toString());
        return pd;
    }
}
```

Rules:
- **Extend `ResponseEntityExceptionHandler`** so Spring's built-in handlers
  for `MethodArgumentNotValidException`, `HttpMessageNotReadableException`,
  etc. remain wired and produce `ProblemDetail` responses.
- **Most specific exception first** — Spring picks by closest match.
- Map every third-party exception that can escape the boundary here, **not**
  in the service layer. Services rethrow as-is or wrap into a domain exception.
- The `build` helper is the place to add cross-cutting fields (timestamp,
  request URI, traceId, error code). Organizations may use a private wrapper
  in their fork that swaps the super-class for an in-house base
  ExceptionHandler that already adds those fields.

### 4. Throw-site policy

| Situation | What to throw |
| --- | --- |
| Input is syntactically invalid (bad enum value, missing required param) | `<Domain>BadRequestException` |
| Caller is authenticated but not allowed for this resource | `<Domain>ForbiddenException` |
| Resource genuinely does not exist | `<Domain>NotFoundException` |
| Downstream dependency returned an error / timed out | `<Domain>Exception` wrapping the cause (→ 500) |
| Programmer error (precondition violation inside the service) | `IllegalStateException` / `IllegalArgumentException` (mapped by stock `ResponseEntityExceptionHandler`) |

## Tests

For the handler, use the `unit-tests` skill with the
`@WebMvcTest(controllers = ..., advice = FooExceptionsHandler.class)` slice
or a full `MockMvcBuilders.standaloneSetup(controller).setControllerAdvice(handler)`
setup. Assert:

- Status code matches.
- `ProblemDetail.detail` equals the formatted message constant.
- `ProblemDetail.title` / `status` are populated by the advice.

For each thrown-exception path inside services, assert in unit tests that
the **correct subclass** is thrown (`assertThrows(FooForbiddenException.class, …)`),
not just `FooException`. The HTTP mapping depends on the exact subclass.

Component tests (see `component-tests`) prove the end-to-end status
mapping for the full matrix (`200 / 400 / 403 / 404 / 500`).

## Do / Don't

✅ One advice class per microservice; it lives in `exception/handler/`.
✅ Always extend `ResponseEntityExceptionHandler` (or your organization's
or your organization's extension of it) to get framework-provided
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

## 6. Templates

- [`BaseDomainException.java.tmpl`](./templates/BaseDomainException.java.tmpl) — Common base class.
- [`NotFoundException.java.tmpl`](./templates/NotFoundException.java.tmpl) — Maps to 404.
- [`ConflictException.java.tmpl`](./templates/ConflictException.java.tmpl) — Maps to 409.
- [`BadRequestException.java.tmpl`](./templates/BadRequestException.java.tmpl) — Maps to 400.
- [`ForbiddenException.java.tmpl`](./templates/ForbiddenException.java.tmpl) — Maps to 403.
- [`ExceptionMessages.java.tmpl`](./templates/ExceptionMessages.java.tmpl) — Message catalogue.
- [`GlobalExceptionHandler.java.tmpl`](./templates/GlobalExceptionHandler.java.tmpl) — The `@RestControllerAdvice`.

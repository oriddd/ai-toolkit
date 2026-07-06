---
name: api-design
description: REST API design rules every Spring Boot service publishes — resource modelling, HTTP-verb semantics, status code catalogue, URL conventions, versioning (URI vs media-type), pagination + filtering + sorting, deprecation headers, error format (RFC 7807 ProblemDetail), HATEOAS posture, OpenAPI-first vs code-first. Use whenever a new endpoint is designed or an existing API is reviewed.
tier: must
applies_to: [rest, monolith]
depends_on: [code-structure, exception-handling]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# API Design Skill (public)

A predictable HTTP API is a feature of the platform. Apply these rules
before writing the controller.

## 1. Resources, not actions

URL paths name **nouns** (resources), HTTP verbs name actions.

```
GET    /api/v1/documents                # list
POST   /api/v1/documents                # create
GET    /api/v1/documents/{id}           # read
PUT    /api/v1/documents/{id}           # full replace
PATCH  /api/v1/documents/{id}           # partial update
DELETE /api/v1/documents/{id}           # delete
GET    /api/v1/documents/{id}/files     # sub-collection
GET    /api/v1/documents/{id}/files/{fileId}/formatted?targetFormat=pdf
```

❌ `POST /api/v1/convertDocument` — verb in URL = anti-pattern.
✅ `POST /api/v1/documents/{id}/conversions` — start a conversion sub-resource.

## 2. Status codes (catalogue)

| Code | When |
| --- | --- |
| **200 OK** | Successful read or sync action with body |
| **201 Created** | Resource created — include `Location` header |
| **202 Accepted** | Async work started — include `Operation-Location` header |
| **204 No Content** | Success, no body (DELETE, PUT replace) |
| **400 Bad Request** | Malformed input, validation failure |
| **401 Unauthorized** | No / invalid credentials |
| **403 Forbidden** | Authenticated but not allowed |
| **404 Not Found** | Resource (or its parent) does not exist |
| **409 Conflict** | Optimistic-lock failure, idempotency-key mismatch, business invariant |
| **415 Unsupported Media Type** | Body content type not accepted |
| **422 Unprocessable Entity** | Syntactically valid, semantically invalid |
| **429 Too Many Requests** | Rate-limited — include `Retry-After` |
| **500 Internal Server Error** | Unhandled failure |
| **503 Service Unavailable** | Downstream unhealthy — include `Retry-After` |

Every 4xx/5xx body is an **RFC 7807 `ProblemDetail`** (see `exception-handling`).

## 3. Versioning

Pick **one** of:

- **URI versioning**: `/api/v1/...`, `/api/v2/...` (default — easiest for
  consumers to reason about).
- **Media-type versioning**: `Accept: application/vnd.example.v1+json`
  (cleaner for cache layers, harder for ad-hoc clients).

Rules:
- Bump the major version only on **breaking** changes.
- Both versions coexist for **at least 6 months**.
- Deprecation announced via `Deprecation: <RFC 8594 date>` + `Sunset: <date>`
  headers on the old version's responses, with a link to migration docs.

## 4. Pagination, filtering, sorting

```
GET /api/v1/documents?status=READY&owner=alice&page=2&size=20&sort=createdAt,desc
```

- Use **Spring `Pageable`** (offset-based) for ≤ 100 000 records, default
  size 20, max 100.
- Use **cursor pagination** (`pageToken` query param, opaque next-token in
  body) when offset is too expensive. Document both in OpenAPI.
- Response wraps the page in a stable shape; never return a bare JSON array
  for a paged endpoint.

## 5. Filtering grammar

Two acceptable shapes:

- **Simple** — `?status=READY&owner=alice` (AND-only). Default.
- **Expression** — `?filter=status eq 'READY' and owner eq 'alice'` (OData-style).
  Required only when callers need OR / nesting.

Map to **Specifications** in the repository (see `persistence`). Never
write `findByStatusAndOwnerAndType...`.

### Complex Query Parameters (OData-lite)

When a simple `GET` needs complex filtering, sorting, or pagination, follow these rules to prevent "query parameter explosion":

1. **Filtering**: Use a flat prefix like `filter.` (e.g., `?filter.status=ACTIVE&filter.type=PDF`).
2. **Sorting**: Use a single `sort` parameter with `field,dir` syntax (e.g., `?sort=createdAt,desc&sort=name,asc`).
3. **Pagination**: Always use `page` (0-indexed) and `size`. Defaults: `page=0, size=20`.
4. **Projection**: Use `fields` to limit the returned DTO properties (e.g., `?fields=id,name`).

For extremely complex logic (nested AND/OR, full-text search), abandon `GET` and use **Pattern B**: `POST /resources/search` with a structured JSON request body.

## 6. Request/response shape

- Records, never `Map<String,Object>`.
- All field names are `camelCase` in JSON; Jackson defaults.
- `null` ≠ missing — use `JsonInclude(Include.NON_NULL)` on response DTOs.
- `Optional` only on response DTOs to mean "absent"; never as a request
  field type (Jackson does not deserialize cleanly).
- Dates are **ISO-8601 strings** (`Instant` → `2026-06-10T12:34:56Z`). Never
  epoch millis.

## 6b. Multipart endpoints (file + JSON DTO)

For uploads that combine a binary part and structured metadata, use
`multipart/form-data` with two named parts — never invent ad-hoc
encodings.

```yaml
# api.yaml
requestBody:
  required: true
  content:
    multipart/form-data:
      schema:
        type: object
        required: [file, asset]
        properties:
          file:
            type: string
            format: binary
          asset:
            $ref: '#/components/schemas/AssetCreateRequest'
```

```java
@PostMapping(
    value = "/api/v1/entities/{entityId}/assets",
    consumes = MediaType.MULTIPART_FORM_DATA_VALUE,
    produces = MediaType.APPLICATION_JSON_VALUE)
public AssetResponse createAsset(
        @PathVariable String entityId,
        @RequestPart("file") MultipartFile file,
        @RequestPart("asset") @Valid AssetCreateRequest asset) {
    return service.create(entityId, file, asset);
}
```

Rules:

- Two `@RequestPart` parameters: one for the binary, one for the JSON DTO
  — both named, both required (unless explicitly optional).
- `@Valid` works on `@RequestPart` JSON parts; rely on it for validation
  rather than re-validating inside the service.
- Configure max sizes explicitly (do not rely on Spring defaults):

  ```yaml
  spring:
    servlet:
      multipart:
        max-file-size: 50MB
        max-request-size: 55MB
  ```

- Translate `MaxUploadSizeExceededException` to **`413 Payload Too Large`**
  in your `@RestControllerAdvice` (see `exception-handling`).
- **Stream** large files (`file.getInputStream()` → downstream sink). Never
  call `file.getBytes()` on > 1 MB payloads — it materialises into JVM
  heap.
- Validate the file's `Content-Type` against an allow-list before persisting;
  do not trust the client header alone (sniff the bytes if security
  matters).
- Return a JSON DTO, never the uploaded bytes. The response is a *receipt*,
  not an echo.

Forbidden:

- Accepting `application/octet-stream` with metadata in custom headers.
- Two endpoints — one for the file, one for the metadata — joined by a
  client-managed correlation ID. That moves transactional integrity onto
  the client.
- Returning the uploaded `MultipartFile` content in the response body.
- Persisting `file.getOriginalFilename()` without sanitisation.

## 7. Idempotency for unsafe verbs

`POST` and `PATCH` accept an `Idempotency-Key` header. See
`spring-boot-conventions` §9.

## 8. Async operations

Long-running ops (file conversion, report generation):

```
POST  /api/v1/documents/{id}/conversions
        → 202 Accepted
          Operation-Location: /api/v1/operations/abc123

GET   /api/v1/operations/abc123
        → 200 { "status": "RUNNING|SUCCEEDED|FAILED", "result": …, "error": … }
```

The operation resource is itself a first-class part of the API.

## 9. HATEOAS posture

Default: **flat JSON DTOs**, no `_links`. HATEOAS is required only when
clients are autonomous agents that should discover navigation at runtime
(rare).

## 10. OpenAPI-first vs code-first

| | Code-first (springdoc reads annotations) | Schema-first (write `openapi.yaml`, generate stubs) |
| --- | --- | --- |
| When | Internal API, single team, prototype | Public API, multiple teams, polyglot clients |
| Build | `springdoc-openapi-starter-webmvc-ui` | `openapi-generator-maven-plugin` → server + client stubs |
| Risk | Drift between docs and behaviour | Verbose schema; codegen surprises |

Either way, the **OpenAPI document is the contract**. Pin it as a CI
snapshot test — any change requires a deliberate update + review.

## Do / Don't

✅ Resources are nouns; verbs are HTTP verbs.
✅ Every error is a `ProblemDetail`; every list is paginated.
✅ One canonical versioning scheme per organization.
❌ Never publish an endpoint without an OpenAPI definition.
❌ Never delete or rename a field in a stable major version.
❌ Never invent custom status codes (`299`, `599`) — use the IANA registry.


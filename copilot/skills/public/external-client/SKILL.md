---
name: external-client
description: Generate an SDK-style integration package for an external service (HTTP, gRPC, message broker, file store). Produces the canonical five-layer sub-package — Service (domain facade), CoreService (orchestrator), Client (thin transport), handler/request (RequestBuilder + FilterMapBuilder), handler/response (ResponseParser + ResponseVerifier), Config (transport bean), Constants — so callers see a single domain-friendly service instead of WebClient or SDK noise. Apply whenever a new downstream dependency is introduced.
tier: must
applies_to: [rest, event, scheduler, monolith]
depends_on: [code-structure, observability, pluggable-architecture]
ships_templates: true
hitl: false
version: 2.0
last_reviewed: 2026-07-01
---

# External Client Skill

Every external dependency is wrapped in its own **self-contained sub-package**
under `client/`. The package is a mini-SDK: consumers depend on **one**
domain-friendly `*Service` facade and never see `WebClient`, `Mono`, SDK types,
or remote DTOs. This is the **lego-brick** convention.

## 1. Canonical package structure

```
client/<dependency-name>/
├── <Dep>Service.java                         # public domain facade — the only class callers import
├── constant/
│   └── <Dep>Constants.java                   # field names, query IDs, sentinel values
├── core/
│   ├── <Dep>ClientConfig.java                # @Configuration — transport bean
│   ├── <Dep>Client.java                      # thin HTTP/gRPC transport, one method per remote op
│   └── <Dep>CoreService.java                 # orchestrator: build → call → parse/verify
└── handler/
    ├── request/
    │   ├── <Dep>RequestBuilder.java           # assembles SDK request DTOs from domain primitives
    │   └── <Dep>FilterMapBuilder.java         # fluent filter-map builder (keeps callers clean)
    └── response/
        ├── <Dep>ResponseParser.java           # extracts domain values from response DTOs
        └── <Dep>ResponseVerifier.java         # checks response conditions (hasHits, isSuccess…)
```

Layering — callers only touch the top row; every layer below is invisible:

```
operation / service
      │
      ▼
  <Dep>Service                  ← public API, domain method names
      │
      ▼
  <Dep>CoreService              ← orchestrates: FilterMapBuilder → RequestBuilder → Client → Parser/Verifier
      │                ├──► <Dep>RequestBuilder  (request DTO assembly)
      │                ├──► <Dep>FilterMapBuilder (fluent filter composition)
      ├──► <Dep>Client           ← thin transport, one method per remote endpoint
      ├──► <Dep>ResponseParser   ← extracts values from response DTOs
      └──► <Dep>ResponseVerifier ← boolean checks on response state
```

## 2. The facade — `<Dep>Service`

The one class all callers import. Expresses operations in **domain language**,
hides filter building and response parsing entirely.

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
@Slf4j
public class FooService {
    private final FooCoreService fooCoreService;
    private final FooResponseParser fooResponseParser;

    /** Returns the type string of the entity, or null if blank / not found. */
    public String getEntityType(final String entityId, final CallerContext callerContext) {
        if (StringUtils.isBlank(entityId)) {
            log.error("Cannot determine entity type for blank entityId");
            return null;
        }
        final Map<String, Object> filters = new FooFilterMapBuilder()
                .withEntityId(entityId).build();
        final FooResponseDto response = fooCoreService.fetchSingleDocument(
                filters, callerContext, FooConstants.FIELDS_TYPE_ONLY);
        return fooResponseParser.parseEntityType(response);
    }

    /** Returns true iff at least one document matches the given id + type. */
    public boolean existsByIdAndType(final String entityId, final String entityType,
                                     final CallerContext callerContext) {
        if (StringUtils.isBlank(entityId) || StringUtils.isBlank(entityType)) {
            log.error("entityId and entityType must not be blank");
            return false;
        }
        final Map<String, Object> filters = new FooFilterMapBuilder()
                .withEntityId(entityId).withEntityType(entityType).build();
        return fooCoreService.doDocumentsExist(filters, callerContext);
    }
}
```

Rules:
- **Only** `*Service`, `*CoreService`, and `*Client` may be Spring beans;
  `*FilterMapBuilder` is a plain instantiated object (`new`).
- Guard blank/null inputs here and return a safe sentinel (`null` / `false`)
  **with a log.error**; let `CoreService` stay guard-free.
- Method names use domain vocabulary (`getEntityType`, `isCaseOpen`) — never
  HTTP vocabulary (`post`, `get`, `search`).

## 3. The filter builder — `<Dep>FilterMapBuilder`

A fluent non-Spring builder that composes key→value filter pairs. Keeps
`*Service` readable — no raw `Map.of(KEY, value, KEY2, value2)` noise.

```java
// Not a Spring bean — always instantiated with `new`
public class FooFilterMapBuilder {
    private final Map<String, Object> filters = new HashMap<>();

    public FooFilterMapBuilder withEntityId(final String id) {
        filters.put(FooConstants.FIELD_ID, id);
        return this;
    }

    public FooFilterMapBuilder withEntityType(final String type) {
        filters.put(FooConstants.FIELD_TYPE, type);
        return this;
    }

    public FooFilterMapBuilder withStatus(final String status) {
        filters.put(FooConstants.FIELD_STATUS, status);
        return this;
    }

    public Map<String, Object> build() {
        return Collections.unmodifiableMap(filters);
    }
}
```

- One `with*()` method per filterable field; each delegates to a constant.
- `build()` returns an unmodifiable map — prevents accidental mutation.
- Add new filter fields by adding a new `with*()` method; never break
  existing callers.

## 4. The orchestrator — `<Dep>CoreService`

Wires the request-building → transport call → response-handling pipeline.
Contains no domain decisions; just the sequence.

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
@Slf4j
public class FooCoreService {
    private final FooRequestBuilder fooRequestBuilder;
    private final FooClient fooClient;
    private final FooResponseVerifier fooResponseVerifier;
    private final FooResponseParser fooResponseParser;

    public FooDocumentDto fetchSingleDocument(final Map<String, Object> filters,
                                              final CallerContext callerContext,
                                              final List<String> fields) {
        final FooSearchRequestDto request = fooRequestBuilder
                .buildSearchRequest(filters, callerContext, 1, fields);
        final FooSearchResponseDto response = fooClient.search(request);
        return fooResponseParser.getSingleDocument(response);
    }

    public boolean doDocumentsExist(final Map<String, Object> filters,
                                    final CallerContext callerContext) {
        final FooSearchRequestDto request = fooRequestBuilder
                .buildSearchRequest(filters, callerContext, 0);
        final FooSearchResponseDto response = fooClient.search(request);
        return fooResponseVerifier.hasAnyHits(response);
    }
}
```

## 5. The request builder — `<Dep>RequestBuilder`

A Spring `@Component` that assembles vendor SDK request DTOs from domain
primitives. Never deals with HTTP or response handling.

```java
@Component
public class FooRequestBuilder {

    public FooSearchRequestDto buildSearchRequest(
            final Map<String, Object> filters, final CallerContext callerContext,
            final int docs) {
        final FooSearchRequestDto req = new FooSearchRequestDto();
        req.setDocs(docs);
        req.setOffset(0);
        req.setQueryId(FooConstants.DEFAULT_QUERY_ID);
        req.setPermissions(permissions);
        req.setFilters(buildTermFilters(filters));
        return req;
    }

    public FooSearchRequestDto buildSearchRequest(
            final Map<String, Object> filters, final CallerContext callerContext,
            final int docs, final List<String> fields) {
        final FooSearchRequestDto req = buildSearchRequest(filters, callerContext, docs);
        req.setFields(fields);
        return req;
    }

    private List<FilterDto> buildTermFilters(final Map<String, Object> filters) {
        if (CollectionUtils.isEmpty(filters)) {
            return Collections.emptyList();
        }
        return filters.entrySet().stream()
                .map(e -> new TermFilterDto(e.getKey(), e.getValue()))
                .toList();
    }
}
```

## 6. The transport — `<Dep>Client` + `<Dep>ClientConfig`

### `<Dep>ClientConfig` — one named bean per external system

```java
@Configuration
public class FooClientConfig {

    @Bean
    public WebClient fooWebClient(
            @Value("${foo-service.base-url}") final String baseUrl) {
        return WebClient.builder()
                .baseUrl(baseUrl)
                // add auth filters, codecs, etc. here — never in the Client
                .build();
    }
}
```

### `<Dep>Client` — thin transport, one method per remote endpoint

```java
@Component
@Log4j2
public class FooClient {
    private final WebClient fooWebClient;
    private final String searchEndpoint;

    @Autowired
    public FooClient(final WebClient fooWebClient,
                     @Value("${foo-service.search-endpoint}") final String searchEndpoint) {
        this.fooWebClient = fooWebClient;
        this.searchEndpoint = searchEndpoint;
    }

    public FooSearchResponseDto search(final FooSearchRequestDto request) {
        log.debug("Foo search request: {}", request);
        return fooWebClient.post()
                .uri(searchEndpoint)
                .body(BodyInserters.fromValue(request))
                .exchangeToMono(response -> handleResponse(response, FooSearchResponseDto.class))
                .block();
    }

    private <T> Mono<T> handleResponse(final ClientResponse response,
                                        final Class<T> type) {
        if (response.statusCode().isError()) {
            return response.toEntity(String.class).flatMap(err ->
                    Mono.error(new FooWebClientException(
                            MessageFormat.format(
                                    "Foo service call failed. Status: {0}, Body: {1}",
                                    err.getStatusCode(), err.getBody()),
                            err)));
        }
        return response.bodyToMono(type);
    }
}
```

Rules:
- Use `exchangeToMono` + a private `handleResponse` method — this lets you
  read the error body **and** the status before throwing the domain exception.
- **Always translate non-2xx to a domain exception** before it escapes the
  `client/` package.
- Call `.block()` at the `Client` boundary — callers see a synchronous API.
  If callers are reactive, expose `Mono<T>` consistently instead.
- Endpoint URLs come from `@Value` injected into the constructor (never
  inline strings); mirror them in `*Constants` as documentation anchors.

## 7. Response handlers — `<Dep>ResponseParser` + `<Dep>ResponseVerifier`

Split response concerns into two distinct beans:

| Class | Purpose | Returns |
| --- | --- | --- |
| `*ResponseVerifier` | **Boolean checks** on response state (has any hits? is healthy?) | `boolean` |
| `*ResponseParser` | **Extract domain values** from response DTOs (entity type, binary id, field from nested doc) | domain type or `null` |

```java
@Component
public class FooResponseVerifier {

    public boolean hasAnyHits(final FooSearchResponseDto response) {
        return response != null && response.getTotalHits() > 0;
    }

    public boolean hasDocuments(final FooSearchResponseDto response) {
        return response != null && !CollectionUtils.isEmpty(response.getDocuments());
    }
}
```

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
@Slf4j
public class FooResponseParser {
    private final FooResponseVerifier verifier;

    /** Returns the first document, or null + log.error if none. */
    public FooDocumentDto getSingleDocument(final FooSearchResponseDto response) {
        if (verifier.hasDocuments(response)) {
            return response.getDocuments().getFirst();
        }
        log.error("No documents in response: {}", response);
        return null;
    }

    /** Extracts a field value from nested documents; returns null if absent. */
    public String parseFieldFromNested(final FooDocumentDto doc, final String fieldName) {
        if (doc == null || StringUtils.isBlank(fieldName)) {
            log.warn("Cannot parse field '{}' from null document", fieldName);
            return null;
        }
        return Optional.ofNullable(doc.getNested())
                .orElse(Collections.emptyList()).stream()
                .filter(Objects::nonNull)
                .map(nested -> nested.getFieldValueAsStr(fieldName))
                .filter(StringUtils::isNotBlank)
                .findFirst()
                .orElse(null);
    }
}
```

## 8. Constants — `<Dep>Constants`

All field names, query IDs, sentinel values, and pre-built field lists:

```java
@NoArgsConstructor(access = AccessLevel.PRIVATE)
public final class FooConstants {
    // Remote field names
    public static final String FIELD_ID     = "foo.core.id";
    public static final String FIELD_TYPE   = "foo.core.type";
    public static final String FIELD_STATUS = "foo.core.status";

    // Query IDs / default values
    public static final String DEFAULT_QUERY_ID = "fooMainSearch";

    // Pre-built field lists (reduce object creation at call sites)
    public static final List<String> FIELDS_TYPE_ONLY =
            Collections.singletonList(FIELD_TYPE);
}
```

Never inline string literals anywhere else in the package — all remote field
names and query parameters live here.

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

## 11. Tests

- **`*FilterMapBuilderTest`** — plain unit test; every `with*()` combination,
  `build()` returns an unmodifiable map.
- **`*RequestBuilderTest`** — pure unit; every overload, every branch in
  filter assembly.
- **`*ResponseVerifierTest`** — null response, empty hit list, non-empty hit list.
- **`*ResponseParserTest`** — null doc, missing nested field, found nested field.
- **`*ClientTest`** — mock `WebClient` exchange (use `MockWebServer` or
  `exchangeFunction(...)`): assert URI/body/headers built; assert domain
  exception thrown on 4xx/5xx; assert deserialized response on 200.
- **`*ServiceTest`** — mock `CoreService`; assert domain-language methods
  guard blank inputs and call core methods correctly.

For component tests, provide a `@MockBean` of the `*Service` (not the
transport) in `ComponentTestConfiguration` — tests drive domain semantics,
not HTTP.

## Do / Don't

✅ Callers import only `*Service` — never `*Client`, `*CoreService`, or any
   remote DTO.
✅ Use `exchangeToMono` + a private `handleResponse(response, type)` in
   `*Client` to read error body before throwing a domain exception.
✅ Keep `*FilterMapBuilder` as a non-Spring plain object — instantiated with
   `new` at the call site for fluent, readable filter composition.
✅ Split `*ResponseParser` (extract values) from `*ResponseVerifier`
   (boolean checks) — they have different change rates and test shapes.
✅ All remote field names and query IDs live in `*Constants` — never inline.
❌ Never let `WebClientResponseException`, `Mono`, `Flux`, or remote DTO
   types escape the `client/<dep>/` package boundary.
❌ Never put retry, circuit-breaker, or metrics logic inside `*Client` itself —
   use Resilience4j annotations or the Decorator pattern on a client interface.
❌ Never return a "default" / silent empty value from a fallback — throw a
   domain exception so the `@RestControllerAdvice` maps it to `503`.
❌ Never share one `WebClient` bean across two external dependencies.

## Cross-references

- [`code-structure`](../code-structure/SKILL.md) — layering rules and package
  conventions the `client/` sub-package follows.
- [`exception-handling`](../exception-handling/SKILL.md) — domain exception
  hierarchy; `*Client` throws subclasses.
- [`resilience-patterns`](../resilience-patterns/SKILL.md) — bulkheads,
  timeouts, circuit breakers beyond simple retries.
- [`health-indicator`](../health-indicator/SKILL.md) — add a readiness
  probe for the new dependency.
- [`observability`](../observability/SKILL.md) — correlation IDs propagated
  through client calls; per-call metrics via `request-metrics`.
- [`pluggable-architecture`](../pluggable-architecture/SKILL.md) — when the
  same capability (e.g. search) must support multiple backends, expose
  `*Service` as a port interface and put each backend under `adapter/`.

## 12. Templates

- [`CacheClientConfig.java.tmpl`](./templates/CacheClientConfig.java.tmpl) — Configuration for an external cache.
- [`CacheClient.java.tmpl`](./templates/CacheClient.java.tmpl) — Thin transport implementation.
- [`CacheEntryResponse.java.tmpl`](./templates/CacheEntryResponse.java.tmpl) — Remote DTO.
- [`CacheEntryAdapter.java.tmpl`](./templates/CacheEntryAdapter.java.tmpl) — Translation to domain model.

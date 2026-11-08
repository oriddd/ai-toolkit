# External Client — facade, filter builder, orchestrator, request builder (§2–§5)

Part of the [`external-client`](../SKILL.md) skill. Section numbers are stable; other skills cite them.

## 2. The facade — `<Dep>Service`

The one class all callers import. Expresses operations in **domain language**,
hides filter building and response parsing entirely.

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class FooService {
    private final FooCoreService fooCoreService;
    private final FooResponseParser fooResponseParser;

    /** Returns the type string of the product, or null if not found. */
    public String getProductType(final String productId, final CallerContext callerContext) {
        Assert.hasText(productId, "productId must not be blank");   // validated at the API boundary; reaching here blank is a bug
        final Map<String, Object> filters = new FooFilterMapBuilder()
                .withProductId(productId).build();
        final FooProductDto product = fooCoreService.fetchSingleProduct(
                filters, callerContext, FooConstants.FIELDS_TYPE_ONLY);
        return fooResponseParser.parseProductType(product);
    }

    /** Returns true iff at least one product matches the given id + type. */
    public boolean existsByIdAndType(final String productId, final String productType,
                                     final CallerContext callerContext) {
        Assert.hasText(productId, "productId must not be blank");
        Assert.hasText(productType, "productType must not be blank");
        final Map<String, Object> filters = new FooFilterMapBuilder()
                .withProductId(productId).withProductType(productType).build();
        return fooCoreService.doProductsExist(filters, callerContext);
    }
}
```

Rules:
- `*FilterMapBuilder` is the **one** plain instantiated object (`new`); every other layer class
  (`*Service`, `*CoreService`, `*Client`, `*RequestBuilder`, `*ResponseParser`, `*ResponseVerifier`) is a
  Spring bean.
- Inputs are validated at the API boundary (`input-validation`). The facade only asserts the contract
  (`Assert.hasText` → `IllegalArgumentException`, a logged 500 because it is a bug) and **never** returns a
  silent sentinel (`null` / `false`) for a bad input; let `CoreService` stay guard-free.
- Method names use domain vocabulary (`getProductType`, `isOrderOpen`) — never
  HTTP vocabulary (`post`, `get`, `search`).

## 3. The filter builder — `<Dep>FilterMapBuilder`

A fluent non-Spring builder that composes key→value filter pairs. Keeps
`*Service` readable — no raw `Map.of(KEY, value, KEY2, value2)` noise.

```java
// Not a Spring bean — always instantiated with `new`
public class FooFilterMapBuilder {
    private final Map<String, Object> filters = new HashMap<>();

    public FooFilterMapBuilder withProductId(final String id) {
        filters.put(FooConstants.FIELD_ID, id);
        return this;
    }

    public FooFilterMapBuilder withProductType(final String type) {
        filters.put(FooConstants.FIELD_TYPE, type);
        return this;
    }

    public FooFilterMapBuilder withStatus(final String status) {
        filters.put(FooConstants.FIELD_STATUS, status);
        return this;
    }

    public Map<String, Object> build() {
        return Map.copyOf(filters);   // immutable snapshot (an unmodifiableMap view would still change); rejects nulls
    }
}
```

- One `with*()` method per filterable field; each delegates to a constant.
- `build()` returns an immutable copy (`Map.copyOf`) — prevents accidental mutation, and a `null` filter
  value fails fast.
- Add new filter fields by adding a new `with*()` method; never break
  existing callers.

## 4. The orchestrator — `<Dep>CoreService`

Wires the request-building → transport call → response-handling pipeline.
Contains no domain decisions; just the sequence.

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class FooCoreService {
    private final FooRequestBuilder fooRequestBuilder;
    private final FooClient fooClient;
    private final FooResponseVerifier fooResponseVerifier;
    private final FooResponseParser fooResponseParser;

    public FooProductDto fetchSingleProduct(final Map<String, Object> filters,
                                              final CallerContext callerContext,
                                              final List<String> fields) {
        final FooSearchRequestDto request = fooRequestBuilder
                .buildSearchRequest(filters, callerContext, 1, fields);
        final FooSearchResponseDto response = fooClient.search(request);
        return fooResponseParser.getSingleProduct(response);
    }

    public boolean doProductsExist(final Map<String, Object> filters,
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
@RequiredArgsConstructor
public class FooRequestBuilder {
    private final FooPermissionMapper permissionMapper;   // maps our caller context to Foo's permission scope

    public FooSearchRequestDto buildSearchRequest(
            final Map<String, Object> filters, final CallerContext callerContext,
            final int docs) {
        final FooSearchRequestDto req = new FooSearchRequestDto();
        req.setDocs(docs);
        req.setOffset(0);
        req.setQueryId(FooConstants.DEFAULT_QUERY_ID);
        // scope the downstream query to what the caller may see — never drop the caller's permissions
        req.setPermissions(permissionMapper.toRemote(callerContext));
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

`*RequestBuilderTest` asserts that the permissions derived from each `CallerContext` are set on the request.

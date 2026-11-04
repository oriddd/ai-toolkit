# External Client — transport, response handlers, constants (§6–§8)

Part of the [`external-client`](../SKILL.md) skill. Section numbers are stable; other skills cite them.

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
| `*ResponseParser` | **Extract domain values** from response DTOs (product type, binary id, field from nested doc) | domain type or `null` |

```java
@Component
public class FooResponseVerifier {

    public boolean hasAnyHits(final FooSearchResponseDto response) {
        return response != null && response.getTotalHits() > 0;
    }

    public boolean hasInvoices(final FooSearchResponseDto response) {
        return response != null && !CollectionUtils.isEmpty(response.getInvoices());
    }
}
```

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
@Slf4j
public class FooResponseParser {
    private final FooResponseVerifier verifier;

    /** Returns the first invoice, or null + log.error if none. */
    public FooInvoiceDto getSingleInvoice(final FooSearchResponseDto response) {
        if (verifier.hasInvoices(response)) {
            return response.getInvoices().getFirst();
        }
        log.error("No invoices in response: {}", response);
        return null;
    }

    /** Extracts a field value from nested invoices; returns null if absent. */
    public String parseFieldFromNested(final FooInvoiceDto doc, final String fieldName) {
        if (doc == null || StringUtils.isBlank(fieldName)) {
            log.warn("Cannot parse field '{}' from null invoice", fieldName);
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

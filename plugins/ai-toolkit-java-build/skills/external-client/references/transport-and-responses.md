# External Client — transport, response handlers, constants (§6–§8)

Part of the [`external-client`](../SKILL.md) skill. Section numbers are stable; other skills cite them.

## 6. The transport — `<Dep>Client` + `<Dep>ClientConfig`

> This section shows the **Full 5-Layer** transport (`WebClient` + `exchangeToMono`, needs
> `spring-boot-starter-webflux`). Simple Wrapper / Lite clients use `RestClient` from
> `spring-boot-starter-web` the same way — see the shipped templates (§12) — and must still map every
> non-2xx to a domain exception.

### `<Dep>Properties` + `<Dep>ClientConfig` — one named bean per external system

```java
@ConfigurationProperties(prefix = "foo-service")
public record FooProperties(String baseUrl, String searchEndpoint, Timeouts timeouts) {
    public record Timeouts(Duration connect, Duration read) {}
}

@Configuration
@EnableConfigurationProperties(FooProperties.class)
public class FooClientConfig {

    @Bean
    public WebClient fooWebClient(final WebClient.Builder webClientBuilder, final FooProperties props) {
        // WebClient has no response timeout by default — without these a hung dependency hangs the caller
        final HttpClient httpClient = HttpClient.create()
                .option(ChannelOption.CONNECT_TIMEOUT_MILLIS, (int) props.timeouts().connect().toMillis())
                .responseTimeout(props.timeouts().read());
        // clone Boot's auto-configured builder: a static WebClient.builder() loses Micrometer observation
        // (client metrics + W3C trace propagation)
        return webClientBuilder.clone()
                .baseUrl(props.baseUrl())
                .clientConnector(new ReactorClientHttpConnector(httpClient))
                // add auth filters, codecs, etc. here — never in the Client
                .build();
    }
}
```

### `<Dep>Client` — thin transport, one method per remote endpoint

```java
@Component
@Slf4j
public class FooClient {
    static final String DEPENDENCY = "foo-service";
    private final WebClient fooWebClient;
    private final String searchEndpoint;

    // @Qualifier: every dependency has its own WebClient bean, so injection by type alone is ambiguous
    public FooClient(@Qualifier("fooWebClient") final WebClient fooWebClient, final FooProperties props) {
        this.fooWebClient = fooWebClient;
        this.searchEndpoint = props.searchEndpoint();
    }

    public FooSearchResponseDto search(final FooSearchRequestDto request) {
        log.debug("Foo search request sent (queryId={})", request.getQueryId());   // never log the request or response body: it carries PII
        return fooWebClient.post()
                .uri(searchEndpoint)
                .body(BodyInserters.fromValue(request))
                .exchangeToMono(response -> handleResponse(response, FooSearchResponseDto.class))
                // connect / response timeouts surface as WebClientRequestException — translate them too
                .onErrorMap(WebClientRequestException.class,
                        e -> ExceptionMessages.dependencyUnavailable(DEPENDENCY, e))
                .block();   // servlet stack only: .block() on a Reactor non-blocking thread throws IllegalStateException
    }

    private <T> Mono<T> handleResponse(final ClientResponse response,
                                        final Class<T> type) {
        if (response.statusCode().is2xxSuccessful()) {
            return response.bodyToMono(type);
        }
        if (response.statusCode().is5xxServerError()) {   // transient — the exception Retry is configured for (§10)
            return response.createException().flatMap(ex ->
                    Mono.error(ExceptionMessages.dependencyUnavailable(DEPENDENCY, ex)));
        }
        // 1xx / 3xx / 4xx: never parse as a body. The body can hold PII — only the status goes in the message.
        final int status = response.statusCode().value();
        return response.releaseBody().then(Mono.error(ExceptionMessages.dependencyCallFailed(DEPENDENCY, status)));
    }
}
```

Rules:
- Use `exchangeToMono` + a private `handleResponse` method — this lets you
  read the error body **and** the status before throwing the domain exception.
- **Every call has a timeout**: set the connect and response timeouts on the `HttpClient` (see `FooClientConfig`), never an unbounded `.block()`.
- **Always translate non-2xx to a domain exception** before it escapes the
  `client/` package — anything that is not 2xx is an error, including 1xx/3xx. 5xx and timeouts become
  `UnavailableException` (retryable, → 503 + `Retry-After`), any other status `DependencyException` (→ 500), both
  built by `ExceptionMessages` (`exception-handling`). Both are unchecked — `.block()` would wrap a checked
  exception in a `ReactiveException`.
- Call `.block()` at the `Client` boundary — callers see a synchronous API. This is valid only on the servlet
  stack (Spring MVC threads); on a WebFlux/Reactor thread `.block()` throws. If callers are reactive, expose
  `Mono<T>` consistently instead.
- Endpoint URLs come from the `<Dep>Properties` record injected into the constructor (never
  inline strings, never `@Value`); mirror them in `*Constants` as documentation anchors.

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

    public boolean hasProducts(final FooSearchResponseDto response) {
        return response != null && !CollectionUtils.isEmpty(response.getProducts());
    }
}
```

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class FooResponseParser {
    private final FooResponseVerifier verifier;

    /** Returns the first product, or null + log.error if none. */
    public FooProductDto getSingleProduct(final FooSearchResponseDto response) {
        if (verifier.hasProducts(response)) {
            return response.getProducts().getFirst();
        }
        log.error("No products in response (totalHits={})", response == null ? null : response.getTotalHits());
        return null;
    }

    /** Extracts a field value from nested products; returns null if absent. */
    public String parseFieldFromNested(final FooProductDto doc, final String fieldName) {
        if (doc == null || StringUtils.isBlank(fieldName)) {
            log.warn("Cannot parse field '{}' from null product", fieldName);
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

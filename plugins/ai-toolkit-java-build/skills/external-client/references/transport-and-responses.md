# External Client — transport, response handlers, constants (§6–§8)

Part of the [`external-client`](../SKILL.md) skill. Section numbers are stable; other skills cite them.

## 6. The transport — `<Dep>Client` + `<Dep>ClientConfig`

> Every pattern uses the synchronous `RestClient` from `spring-boot-starter-web` (`spring-boot-conventions`:
> `RestClient` for blocking calls, `WebClient` for reactive callers or when the developer picks it in SKILL.md §0). The Full 5-Layer transport below and the
> Simple Wrapper / Lite templates (§12) share the same rules. A **reactive** (WebFlux) service uses `WebClient`
> instead — see the note at the end of this section.

### `<Dep>Properties` + `<Dep>ClientConfig` — one named bean per external system

```java
@ConfigurationProperties(prefix = "foo-service")
public record FooProperties(String baseUrl, String searchEndpoint, Timeouts timeouts) {
    public record Timeouts(Duration connect, Duration read) {}
}

@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(FooProperties.class)
public class FooClientConfig {

    @Bean("fooRestClient")
    public RestClient fooRestClient(final RestClient.Builder restClientBuilder,
                                    final ClientHttpRequestFactoryBuilder<?> requestFactoryBuilder,
                                    final ClientHttpRequestFactorySettings requestFactorySettings,
                                    final FooProperties props) {
        // RestClient has no timeouts by default — without these a hung dependency hangs the caller.
        // Boot's factory builder + settings keep the detected HTTP client (pooling) and spring.http.client.*;
        // only the timeouts are per dependency.
        final ClientHttpRequestFactorySettings settings = requestFactorySettings
                .withConnectTimeout(props.timeouts().connect())
                .withReadTimeout(props.timeouts().read())
                .withRedirects(ClientHttpRequestFactorySettings.Redirects.DONT_FOLLOW);
        // clone Boot's auto-configured builder: a static RestClient.builder() loses Micrometer observation
        // (client metrics + W3C trace propagation)
        return restClientBuilder.clone()
                .baseUrl(props.baseUrl())
                .requestFactory(requestFactoryBuilder.build(settings))
                // add auth interceptors (§6b), default headers, etc. here — never in the Client
                .build();
    }
}
```

Never `new SimpleClientHttpRequestFactory()`: it swaps Boot's detected client (Apache HttpClient / Jetty / Reactor /
JDK) for `HttpURLConnection` — no connection pooling, no `PATCH`, and `spring.http.client.*` is ignored.
**Boot 4.x (opt-in):** the settings type is `HttpClientSettings` (same `with*Timeout` methods; `withRedirects(HttpRedirects.DONT_FOLLOW)`); the rest is unchanged.

### `<Dep>Client` — thin transport, one method per remote endpoint

```java
@Component
@Slf4j
public class FooClient {
    static final String DEPENDENCY = "foo-service";
    private final RestClient fooRestClient;
    private final String searchEndpoint;

    // @Qualifier: every dependency has its own RestClient bean, so injection by type alone is ambiguous
    public FooClient(@Qualifier("fooRestClient") final RestClient fooRestClient, final FooProperties props) {
        this.fooRestClient = fooRestClient;
        this.searchEndpoint = props.searchEndpoint();
    }

    public FooSearchResponseDto search(final FooSearchRequestDto request)
            throws UnavailableException, DependencyException {
        log.debug("Foo search request sent (queryId={})", request.getQueryId());   // never log the request or response body: it carries PII
        final Reply<FooSearchResponseDto> reply;
        try {
            reply = fooRestClient.post()
                    .uri(searchEndpoint)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(request)
                    .exchange((req, response) -> readReply(response, FooSearchResponseDto.class));
        } catch (ResourceAccessException e) {   // connect / read timeout, connection refused
            throw ExceptionMessages.dependencyUnavailable(DEPENDENCY, e);
        }
        return bodyOrThrow(reply);
    }

    private record Reply<T>(HttpStatusCode status, @Nullable T body) {}

    /** Runs inside the exchange lambda, which cannot throw a checked domain exception: read the status, decide outside. */
    private <T> Reply<T> readReply(final ConvertibleClientHttpResponse response, final Class<T> type)
            throws IOException {
        final HttpStatusCode status = response.getStatusCode();
        return new Reply<>(status, status.is2xxSuccessful() ? response.bodyTo(type) : null);   // 1xx / 3xx / 4xx: never parse as a body
    }

    private <T> T bodyOrThrow(final Reply<T> reply) throws UnavailableException, DependencyException {
        final HttpStatusCode status = reply.status();
        if (status.is2xxSuccessful()) {
            final T body = reply.body();
            if (body == null) {   // an empty 2xx where a body is required is a broken contract, never a silent null
                throw ExceptionMessages.dependencyCallFailed(DEPENDENCY, status.value());
            }
            return body;
        }
        if (status.is5xxServerError()) {   // transient — the exception Retry is configured for (§10)
            throw ExceptionMessages.dependencyUnavailable(DEPENDENCY, null);
        }
        // The body can hold PII — only the status goes in the message.
        throw ExceptionMessages.dependencyCallFailed(DEPENDENCY, status.value());
    }
}
```

`ConvertibleClientHttpResponse` is `RestClient.RequestHeadersSpec.ConvertibleClientHttpResponse`.

Rules:
- Use `exchange` + a private `readReply` method — this lets you read the status **and**, when a decision needs
  it, the error body, then throw the domain exception **after** the lambda (it cannot declare a checked exception).
  (`retrieve()` + `onStatus(...)` is the equivalent for a one-off call; its handler cannot throw a checked exception
  either, so it must record the status and throw afterwards.)
- **Redirects are not followed** (`withRedirects(...DONT_FOLLOW)` above): Boot's default follows them, so a 302 would be
  answered by whatever it points to — a silent success, or a call to a host outside the allow-list — instead of the
  `DependencyException` the 3xx rule below promises. A test with a `302` stub fails without this line.
- **Every call has a timeout**: set the connect and read timeouts on the request factory (see `FooClientConfig`),
  never rely on the defaults (none).
- **Always translate non-2xx to a domain exception** before it escapes the
  `client/` package — anything that is not 2xx is an error, including 1xx/3xx. 5xx and timeouts become
  `UnavailableException` (retryable, → 503 + `Retry-After`), any other status `DependencyException` (→ 500), both
  built by `ExceptionMessages` (`exception-handling`). Both are checked: `Client`, `CoreService` and `Service` methods declare
  `throws UnavailableException, DependencyException`.
- The `Client` boundary is **synchronous** — callers see plain return values. `RestClient` blocks on the calling
  (servlet) thread, so there is no `.block()` to place.
- Endpoint URLs come from the `<Dep>Properties` record injected into the constructor (never
  inline strings, never `@Value`); mirror them in `*Constants` as documentation anchors.

**Reactive callers (WebFlux) only:** build a `WebClient` from Boot's `WebClient.Builder` (`.clone()`, timeouts on the
connector), use `exchangeToMono` + the same status mapping (`response.createException()` / `releaseBody()`),
translate `WebClientRequestException` to `UnavailableException`, and expose `Mono<T>` consistently. Never `.block()`
inside a reactive pipeline — on a Reactor thread it throws `IllegalStateException`. Never add
`spring-boot-starter-webflux` to a servlet service just to get `WebClient`.

## 6b. Outbound OAuth2 — client credentials

When the dependency requires a service token (`authMode = oauth2` in the `new-microservice-client` interview), let
Spring Security fetch, cache and refresh it; the `Client` stays unaware of tokens.

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-oauth2-client</artifactId>
</dependency>
```

Merge under the existing top-level `spring:` key of `application.yaml`:

```yaml
spring:
  security:
    oauth2:
      client:
        registration:
          foo-service:                                 # registration id = FooClient.DEPENDENCY
            provider: foo-idp
            client-id: ${FOO_CLIENT_ID}
            client-secret: ${FOO_CLIENT_SECRET}        # from a Secret / vault via env, never in the repo
            authorization-grant-type: client_credentials
            scope: foo.read
        provider:
          foo-idp:
            token-uri: ${FOO_TOKEN_URI}
```

```java
@Bean
OAuth2AuthorizedClientManager serviceAuthorizedClientManager(
        final ClientRegistrationRepository clientRegistrations,
        final OAuth2AuthorizedClientService authorizedClients) {
    // service-to-service: works outside an HTTP request (schedulers, consumers); caches the token until it expires
    final AuthorizedClientServiceOAuth2AuthorizedClientManager manager =
            new AuthorizedClientServiceOAuth2AuthorizedClientManager(clientRegistrations, authorizedClients);
    manager.setAuthorizedClientProvider(OAuth2AuthorizedClientProviderBuilder.builder()
            .clientCredentials()
            .build());
    return manager;
}

@Bean("fooRestClient")
public RestClient fooRestClient(final RestClient.Builder restClientBuilder,
                                final ClientHttpRequestFactoryBuilder<?> requestFactoryBuilder,
                                final ClientHttpRequestFactorySettings requestFactorySettings,
                                final OAuth2AuthorizedClientManager serviceAuthorizedClientManager,
                                final OAuth2AuthorizedClientService authorizedClients,
                                final FooProperties props) {
    final OAuth2ClientHttpRequestInterceptor oauth2 =
            new OAuth2ClientHttpRequestInterceptor(serviceAuthorizedClientManager);
    oauth2.setClientRegistrationIdResolver(request -> FooClient.DEPENDENCY);
    // without this a revoked / rotated token stays cached and every call answers 401 until it expires
    oauth2.setAuthorizationFailureHandler(
            OAuth2ClientHttpRequestInterceptor.authorizationFailureHandler(authorizedClients));
    return restClientBuilder.clone()
            .baseUrl(props.baseUrl())
            .requestFactory(requestFactoryBuilder.build(requestFactorySettings
                    .withConnectTimeout(props.timeouts().connect())
                    .withReadTimeout(props.timeouts().read())
                    .withRedirects(ClientHttpRequestFactorySettings.Redirects.DONT_FOLLOW)))
            .requestInterceptor(oauth2)
            .build();
}
```

Rules:
- `OAuth2ClientHttpRequestInterceptor` (Spring Security 6.4+, in Boot 3.5) adds `Authorization: Bearer …` on the
  cloned builder of **this** dependency only — never on a shared builder, or every downstream receives the token.
- Boot auto-configures `ClientRegistrationRepository` and `OAuth2AuthorizedClientService` from the properties (also
  in a non-web scheduler or consumer: proven with `webEnvironment = NONE`). Its default `oauth2Login` filter chain backs off when the service defines its
  own `SecurityFilterChain` (`permissions`).
- The manager caches the token in the `OAuth2AuthorizedClientService` and requests a new one shortly before expiry —
  never fetch a token per call or cache it yourself.
- Client id / secret come from environment variables backed by a Kubernetes Secret (`cd`), never from
  `application.yaml` or the repo.
- **401 recovery.** The failure handler above drops the cached token when the API answers 401, but the request that got
  the 401 is not replayed. Replay it once in the `Client` (the second send fetches a new token); a 401 that persists
  is a `DependencyException`:

  ```java
  Reply<FooSearchResponseDto> reply = send(request);
  if (reply.status().value() == HttpStatus.UNAUTHORIZED.value()) {
      reply = send(request);          // the failure handler removed the token: this attempt authenticates afresh
  }
  return bodyOrThrow(reply);
  ```
- A failed token request (identity provider down or answering an error) surfaces as an
  `OAuth2AuthorizationException` (`ClientAuthorizationException`) from the interceptor, not as
  `ResourceAccessException`: catch both around the call and map them to `UnavailableException`
  (`catch (ResourceAccessException | ClientAuthorizationException e)`); the API is not called at all in that case.
- Proven against a stub token endpoint + stub API: one token request for three calls (Basic auth + `scope` in the
  request), a new token once the old one is within the 60 s clock skew of its expiry, a revoked token replaced and the
  call succeeding on the replay, a token endpoint answering 401 or 500 → `UnavailableException`, API 503 →
  `UnavailableException`, API 403 → `DependencyException`.

## 7. Response handlers — `<Dep>ResponseParser` + `<Dep>ResponseVerifier`

Split response concerns into two distinct beans:

| Class | Purpose | Returns |
| --- | --- | --- |
| `*ResponseVerifier` | **Boolean checks** on response state (has any hits? is healthy?) | `boolean` |
| `*ResponseParser` | **Extract domain values** from response DTOs (product type, binary id, field from nested doc) | domain type, or `Optional` when the value may be absent |

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
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
@Slf4j
public class FooResponseParser {
    private final FooResponseVerifier verifier;

    /** Returns the first product, or empty + log.error if none. */
    public Optional<FooProductDto> getSingleProduct(final FooSearchResponseDto response) {
        if (verifier.hasProducts(response)) {
            return Optional.of(response.getProducts().getFirst());
        }
        log.error("No products in response (totalHits={})", response == null ? null : response.getTotalHits());
        return Optional.empty();
    }

    public Optional<String> parseProductType(final FooProductDto product) {
        return parseFieldFromNested(product, FooConstants.FIELD_TYPE);
    }

    /** Extracts a field value from nested products; empty if absent. */
    public Optional<String> parseFieldFromNested(final FooProductDto doc, final String fieldName) {
        if (doc == null || fieldName == null || fieldName.isBlank()) {
            log.warn("Cannot parse field '{}' from null product", fieldName);
            return Optional.empty();
        }
        return Optional.ofNullable(doc.getNested())
                .orElse(Collections.emptyList()).stream()
                .filter(Objects::nonNull)
                .map(nested -> nested.getFieldValueAsStr(fieldName))
                .filter(value -> value != null && !value.isBlank())
                .findFirst();
    }
}
```

An absent value is `Optional.empty()`, never a bare `null`: a `null` from a non-`@Nullable` method fails the NullAway
build (`static-analysis`), and the caller decides what "absent" means (404, `false`, a default from config). A
missing value the caller cannot do without is a domain exception, not an empty result.

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

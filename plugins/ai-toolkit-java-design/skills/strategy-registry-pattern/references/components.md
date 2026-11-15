# Strategy + Registry + Handler/Filter Pattern (Foundational) — Component responsibilities

Part of the [`strategy-registry-pattern`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## Component Responsibilities

### 1. **Handler (or Filter)** — The Dispatcher

**Responsibility:** Orchestrate the flow. Resolve context, find the right strategy, delegate.

**Rules:**
- ✅ Handles the request lifecycle (for Filters: measure time, ensure finally block)
- ✅ Delegates to Resolver → Registry → Strategy
- ✅ **Never** contains strategy-specific logic or if/else on strategy type
- ✅ Logs warnings when no strategy is found (Handler: or fails with a domain exception when a strategy is mandatory)
- ✅ Is a `@Component` or extends `OncePerRequestFilter`
- ✅ Filters: times with a monotonic clock (`System.nanoTime()` or a Micrometer `Timer.Sample`), never `currentTimeMillis()`;
  record status 500 when the chain throws (the response still says 200 at that point); record async requests on completion;
  and run **before Spring Security** so 401/403 rejections are measured too. `request-metrics` §4 is the full metrics filter.

**Example (Handler)** — the types and signatures of the `permissions` skill; `ForbiddenException` and
`ExceptionMessages` come from `exception-handling` (unchecked, so no `throws` clause):
```java
@Component
@RequiredArgsConstructor
public class PermissionsHandler {
    private final CallerContextResolver callerContextResolver;
    private final PermissionsRegistry permissionsRegistry;

    public void handle(final String resourceId) {
        final CallerContext ctx = callerContextResolver.resolve();
        if (ctx == null) {
            throw ExceptionMessages.callerContextNotFound();                 // 403
        }
        final PermissionsCheckStrategy strategy = permissionsRegistry.getStrategy(ctx)
                .orElseThrow(() -> ExceptionMessages.unrecognizedCallerContext(ctx));   // 403
        strategy.verifyPermissions(resourceId);
    }
}
```

**Example (Filter):**
```java
@Component
@Order(SecurityProperties.DEFAULT_FILTER_ORDER - 1)   // before Spring Security, so 401/403 rejections are recorded too
@RequiredArgsConstructor
@Slf4j
public class MetricsFilter extends OncePerRequestFilter {
    private final MetricNameResolver metricNameResolver;
    private final MetricsRecorderRegistry metricsRecorderRegistry;

    @Override
    protected void doFilterInternal(HttpServletRequest request, 
                                    HttpServletResponse response, 
                                    FilterChain filterChain) 
            throws ServletException, IOException {
        final long startNanos = System.nanoTime();   // monotonic; currentTimeMillis() jumps with wall-clock changes
        try {
            filterChain.doFilter(request, response);
        } catch (final ServletException | IOException | RuntimeException e) {
            // the container has not turned the exception into a 500 yet, so the response still says 200
            if (!response.isCommitted()) {
                response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            }
            throw e;
        } finally {
            if (request.isAsyncStarted()) {
                // DeferredResult / CompletableFuture: the response is not finished yet — record when it completes
                request.getAsyncContext().addListener(new OnCompleteListener(() -> record(request, response, startNanos)));
            } else {
                record(request, response, startNanos);
            }
        }
    }

    private void record(final HttpServletRequest request, final HttpServletResponse response, final long startNanos) {
        final long durationMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startNanos);
        metricNameResolver.resolve(request)
                .flatMap(metricsRecorderRegistry::getRecorder)
                .ifPresentOrElse(
                        recorder -> recorder.recordMetrics(durationMs, request, response),
                        () -> log.warn("No metrics recorder for URI {}", request.getRequestURI()));
    }

    /** Runs the action once the async request is complete (also after a timeout or an error). */
    private record OnCompleteListener(Runnable action) implements AsyncListener {
        @Override public void onComplete(final AsyncEvent event) { action.run(); }
        @Override public void onTimeout(final AsyncEvent event) { }
        @Override public void onError(final AsyncEvent event) { }
        @Override public void onStartAsync(final AsyncEvent event) { }
    }
}
```

`OncePerRequestFilter` skips the async re-dispatch by default, so each request is recorded once. Running before
Spring Security means the principal is not on this (outer) request — see the `ClientIdParser` in §6 for how the
client id is still tagged.

### 2. **Resolver** — Context Determination

**Responsibility:** Determine which strategy to use based on input context.

**Rules:**
- ✅ Reads request/context and returns a discriminator (String, Enum, etc.)
- ✅ Returns `Optional.empty()` when no match (Handler/Filter logs warning) — never `null`
- ✅ When the discriminator comes from an ordered rule list (URI patterns), the first match wins, so the list is
  ordered most-specific-first — never a `Map.of(...)`, whose iteration order is unspecified
- ✅ **Never** contains business logic
- ✅ Is a `@Component`

**Examples:**
- `MetricNameResolver` — URI pattern → metric name (String)
- `CallerContextResolver` — Authentication → CallerContext (Enum)
- `LayoutResolver` — Query param `?layout=X` → LayoutType (Enum)
- `ApiVersionResolver` — Accept header / URI → ApiVersion (Enum)

```java
@Component
@RequiredArgsConstructor
public class MetricNameResolver {
    private final MonitoringConfig monitoringConfig;

    public Optional<String> resolve(final HttpServletRequest request) {
        if (request == null || request.getRequestURI() == null) {
            return Optional.empty();
        }
        // the patterns are written without server.servlet.context-path
        final String uri = request.getRequestURI().substring(request.getContextPath().length());
        return monitoringConfig.patternToMetricName().stream()      // ordered list: most specific pattern first
                .filter(entry -> entry.getKey().matcher(uri).matches())
                .map(Map.Entry::getValue)
                .findFirst();
    }
}
```

### 3. **Registry** — Strategy Routing

**Responsibility:** Hold all strategies and route to the right one based on the discriminator.

**Rules:**
- ✅ Injects `List<Strategy>` via constructor — Spring auto-discovers all implementations
- ✅ Indexes the strategies by their discriminator (`getSupported<X>()`) once, in the constructor
- ✅ **Fails at startup** (`IllegalStateException`) when two strategies claim the same discriminator — otherwise
  routing would depend on bean order
- ✅ Returns `Optional.empty()` when no strategy matches — never `null`
- ✅ **Never** contains if/else or switch on strategy type
- ✅ Is a `@Component`

```java
@Component
public class MetricsRecorderRegistry {
    private final Map<String, MetricsRecorder> recordersByMetricName;

    public MetricsRecorderRegistry(final List<MetricsRecorder> metricsRecorders) {
        this.recordersByMetricName = metricsRecorders.stream()
                .collect(Collectors.toUnmodifiableMap(
                        MetricsRecorder::getSupportedMetricName,
                        Function.identity(),
                        (first, second) -> {
                            throw new IllegalStateException("Two recorders for metric '"
                                    + first.getSupportedMetricName() + "': "
                                    + first.getClass().getName() + ", " + second.getClass().getName());
                        }));
    }

    public Optional<MetricsRecorder> getRecorder(final String metricName) {
        return Optional.ofNullable(metricName).map(recordersByMetricName::get);
    }
}
```

When one strategy serves several discriminator values (the `permissions` strategies return
`List<CallerContext> supportedContexts()`), index every value the same way and fail on any value claimed twice.

### 4. **Strategy Interface** — The Contract

**Responsibility:** Define the contract that all strategies must implement.

**Rules:**
- ✅ Defines the core behavior method (e.g., `recordMetrics`, `verifyPermissions`, `map`)
- ✅ Declares its discriminator with **one** contract: `getSupported<X>()` returning the single value it serves
  (`getSupportedMetricName()`, `getSupportedLayoutType()`, `getSupportedVersion()`), or `supported<X>s()` returning a
  collection when one strategy serves several values (`supportedContexts()` in `permissions`). The Registry indexes on it.
- ✅ Provides a default `canHandle(discriminator)` derived from that method — for tests and simple lookups; never
  override it with different logic
- ✅ Is an `interface` (not an abstract class unless shared state is needed)

```java
public interface MetricsRecorder {
    void recordMetrics(long durationMs, HttpServletRequest request, HttpServletResponse response);
    String getSupportedMetricName();

    default boolean canHandle(final String metricName) {
        final String supported = getSupportedMetricName();
        return supported != null && !supported.isBlank()      // String::isBlank — no commons-lang3 needed
                && metricName != null && !metricName.isBlank()
                && supported.equals(metricName);
    }
}
```

### 5. **Concrete Strategies** — Implementations

**Responsibility:** Implement the behavior for a specific use case.

**Rules:**
- ✅ Each strategy is a `@Component`
- ✅ Implements the Strategy interface
- ✅ Returns its discriminator value via `getSupported<X>()` (or `supported<X>s()` for several values, see §4)
- ✅ **Never** references other strategies directly
- ✅ Delegates tag/data extraction to Parsers, not inline

```java
@Component
@RequiredArgsConstructor
@Slf4j
public class ExportInvoiceMetricsRecorder implements MetricsRecorder {
    private final MetricsTimerHelper metricsTimerHelper;
    private final ExportFormatParser exportFormatParser;

    @Override
    public String getSupportedMetricName() {
        return MonitoringConstants.METRIC_EXPORT_INVOICE;
    }

    @Override
    public void recordMetrics(final long durationMs,
                              final HttpServletRequest request,
                              final HttpServletResponse response) {
        final Tag formatTag = Tag.of("format",
                exportFormatParser.parseExportFormat(request));
        final Timer timer = metricsTimerHelper.buildTimerWithExtraTags(
                getSupportedMetricName(), request, response, formatTag);
        timer.record(durationMs, TimeUnit.MILLISECONDS);
    }
}
```

### 6. **Parsers** — Data Extraction

**Responsibility:** Extract specific data from request/response/context.

**Rules:**
- ✅ One parser per extractable concept (HTTP method, client ID, target format, layout type)
- ✅ Each parser is a `@Component`
- ✅ Returns a non-blank sentinel value (`UNKNOWN`, `DEFAULT`) on failure — **never** `null` or `""`
- ✅ Swallows exceptions and returns the sentinel, logging at `DEBUG` (or a rate-limited `WARN` plus a failure counter) —
  never `ERROR` per request: one malformed header on every call would flood the logs
- ✅ Method naming: `parse<Concept>(request|response|...)`

```java
@Component
@Slf4j
public class ClientIdParser {
    /** Request attribute holding the client id captured inside the security chain (see ClientIdCaptureInterceptor). */
    public static final String CLIENT_ID_ATTRIBUTE = ClientIdParser.class.getName() + ".clientId";
    private static final String AZP = "azp";

    // Reads the principal from the request, never SecurityContextHolder (that stays in permission/,
    // ArchUnit rule securityHolderLivesInPermissionOnly). Spring Security's request wrapper returns
    // the current Authentication from getUserPrincipal().
    public String parseClientId(final HttpServletRequest request) {
        if (request != null && request.getAttribute(CLIENT_ID_ATTRIBUTE) instanceof String captured) {
            return captured;    // the metrics filter runs outside Spring Security and sees no principal itself
        }
        try {
            final Principal principal = request == null ? null : request.getUserPrincipal();
            if (principal instanceof JwtAuthenticationToken jwt
                    && jwt.getTokenAttributes() != null
                    && jwt.getTokenAttributes().get(AZP) != null) {
                return String.valueOf(jwt.getTokenAttributes().get(AZP));
            }
            if (principal instanceof UsernamePasswordAuthenticationToken) {   // HTTP Basic
                return MonitoringConstants.BASIC;
            }
        } catch (final RuntimeException e) {
            log.debug("Failed to extract clientId", e);
        }
        return MonitoringConstants.UNKNOWN;
    }
}
```

The metrics filter runs before Spring Security (§1), so the request it holds carries no principal. A
`HandlerInterceptor` captures the client id while the request is inside the security chain; the request attribute is
shared by the wrapped and the outer request. Requests rejected by security never reach it and are tagged `UNKNOWN`:

```java
@Component
@RequiredArgsConstructor
public class ClientIdCaptureInterceptor implements HandlerInterceptor {
    private final ClientIdParser clientIdParser;

    @Override
    public boolean preHandle(final HttpServletRequest request, final HttpServletResponse response, final Object handler) {
        request.setAttribute(ClientIdParser.CLIENT_ID_ATTRIBUTE, clientIdParser.parseClientId(request));
        return true;
    }
}
// config/: a WebMvcConfigurer registers it — registry.addInterceptor(clientIdCaptureInterceptor)
```

**Web-slice tests.** Every `@WebMvcTest` loads `Filter`s, `HandlerInterceptor`s and `WebMvcConfigurer`s — so the
`MetricsFilter`, the `ClientIdCaptureInterceptor` and the `WebMvcConfigurer` that registers it — but **not** the
plain `@Component`s they inject (`ClientIdParser`, `MetricNameResolver`, `MetricsRecorderRegistry`, …). Without them
the slice context fails with `NoSuchBeanDefinitionException`. `@Import` those collaborators (or `@MockitoBean` them)
in each slice test — `input-validation` §5c has a full slice example.

### 7. **Helpers** — Shared Logic (Optional)

**Responsibility:** Provide shared utilities or tag-building logic used by multiple strategies.

**Rules:**
- ✅ Only create when multiple strategies need the same logic
- ✅ Is a `@Component`
- ✅ Composes Parsers to build common tag sets or structures

```java
@Component
@RequiredArgsConstructor
public class MetricsTagsHelper {
    private final RequestMethodParser requestMethodParser;
    private final ResponseStatusParser responseStatusParser;
    private final ClientIdParser clientIdParser;

    public Set<Tag> buildGenericTags(final HttpServletRequest request,
                                     final HttpServletResponse response) {
        return Set.of(
            Tag.of("requestMethod", requestMethodParser.parseRequestMethod(request)),
            Tag.of("responseStatus", responseStatusParser.parseResponseStatus(response)),
            Tag.of("clientId", clientIdParser.parseClientId(request))
        );
    }
}
```

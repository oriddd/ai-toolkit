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
`ExceptionMessages` come from `exception-handling` (checked, so the methods declare `throws ForbiddenException`):
```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class PermissionsHandler {
    private final CallerContextResolver callerContextResolver;
    private final PermissionsRegistry permissionsRegistry;

    public void handle(final String resourceId) throws ForbiddenException {
        final CallerContext ctx = callerContextResolver.resolve();
        if (ctx == null) {
            throw ExceptionMessages.callerContextNotFound();                 // 403
        }
        final PermissionsCheckStrategy strategy = permissionsRegistry.getStrategy(ctx);
        if (strategy == null) {
            throw ExceptionMessages.unrecognizedCallerContext(ctx);          // 403
        }
        strategy.verifyPermissions(resourceId);
    }
}
```

**Example (Filter):**
```java
@Component
@Order(SecurityProperties.DEFAULT_FILTER_ORDER - 1)   // before Spring Security, so 401/403 rejections are recorded too
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
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
        final String metricName = metricNameResolver.resolve(request);
        final MetricsRecorder recorder = metricsRecorderRegistry.getRecorder(metricName);
        if (recorder == null) {
            log.warn("No metrics recorder for URI {}", request.getRequestURI());
            return;
        }
        recorder.recordMetrics(durationMs, request, response);
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
- ✅ Returns `null` when no match (Handler/Filter logs warning), declared `@Nullable`. Exception: a resolver that
  parses client HTTP input (`LayoutResolver`, `ApiVersionResolver`) throws the 4xx domain exception for an unknown
  value, because the client sent something invalid (`response-layout`: 400, `response-mapper`: 404 / 406)
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
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class MetricNameResolver {
    private final MonitoringConfig monitoringConfig;

    public @Nullable String resolve(final @Nullable HttpServletRequest request) {
        if (request == null || request.getRequestURI() == null) {
            return null;
        }
        // the patterns are written without server.servlet.context-path
        final String uri = request.getRequestURI().substring(request.getContextPath().length());
        return monitoringConfig.patternToMetricName().stream()      // ordered list: most specific pattern first
                .filter(entry -> entry.getKey().matcher(uri).matches())
                .map(Map.Entry::getValue)
                .findFirst()
                .orElse(null);
    }
}
```

### 3. **Registry** — Strategy Routing

**Responsibility:** Hold all strategies and route to the right one based on the discriminator.

**Rules:**
- ✅ Injects `List<Strategy>` via constructor — Spring auto-discovers all implementations
- ✅ Routes by calling `canHandle(discriminator)` on each strategy and returning the first that accepts
- ✅ **Fails at startup** (`IllegalStateException`) when two strategies declare the same discriminator
  (`getSupported<X>()`) — otherwise `findFirst()` would depend on bean order
- ✅ Returns `null` when no strategy matches, declared `@Nullable` (`org.jspecify.annotations.Nullable`)
- ✅ **Never** contains if/else or switch on strategy type
- ✅ Is a `@Component`

```java
@Component
public class MetricsRecorderRegistry {
    private final List<MetricsRecorder> metricsRecorders;

    public MetricsRecorderRegistry(final List<MetricsRecorder> metricsRecorders) {
        final Map<String, MetricsRecorder> declared = new HashMap<>();
        for (final MetricsRecorder recorder : metricsRecorders) {
            final MetricsRecorder first = declared.putIfAbsent(recorder.getSupportedMetricName(), recorder);
            if (first != null) {
                throw new IllegalStateException("Two recorders for metric '"
                        + recorder.getSupportedMetricName() + "': "
                        + first.getClass().getName() + ", " + recorder.getClass().getName());
            }
        }
        this.metricsRecorders = List.copyOf(metricsRecorders);
    }

    public @Nullable MetricsRecorder getRecorder(final @Nullable String metricName) {
        return metricsRecorders.stream()
                .filter(r -> r.canHandle(metricName))
                .findFirst()
                .orElse(null);
    }
}
```

When one strategy serves several discriminator values (the `permissions` strategies return
`List<CallerContext> supportedContexts()`), check every declared value the same way and fail on any value declared
twice. The check reads the declared values only: a strategy that overrides `canHandle` with its own logic can overlap
another one unseen, so override it only to add composite matching.

### 4. **Strategy Interface** — The Contract

**Responsibility:** Define the contract that all strategies must implement.

**Rules:**
- ✅ Defines the core behavior method (e.g., `recordMetrics`, `verifyPermissions`, `map`)
- ✅ Declares its discriminator: `getSupported<X>()` returning the single value it serves
  (`getSupportedMetricName()`, `getSupportedLayoutType()`, `getSupportedVersion()`), or `supported<X>s()` returning a
  collection when one strategy serves several values (`supportedContexts()` in `permissions`)
- ✅ Defines `canHandle(discriminator)` — used by the Registry for routing
- ✅ Provides a default `canHandle` implementation derived from the declared discriminator, so a strategy only
  declares it
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
- ✅ Returns its discriminator value via `getSupported<X>()` (or `supported<X>s()` for several values) and inherits `canHandle`, see §4
- ✅ **Never** references other strategies directly
- ✅ Delegates tag/data extraction to Parsers, not inline

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
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
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
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
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
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

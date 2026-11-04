# Strategy + Registry + Handler/Filter Pattern (Foundational) — Component responsibilities

Part of the [`strategy-registry-pattern`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## Component Responsibilities

### 1. **Handler (or Filter)** — The Dispatcher

**Responsibility:** Orchestrate the flow. Resolve context, find the right strategy, delegate.

**Rules:**
- ✅ Handles the request lifecycle (for Filters: measure time, ensure finally block)
- ✅ Delegates to Resolver → Registry → Strategy
- ✅ **Never** contains strategy-specific logic or if/else on strategy type
- ✅ Logs warnings when no strategy is found
- ✅ Is a `@Component` or extends `OncePerRequestFilter`

**Example (Handler):**
```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class PermissionsHandler {
    private final CallerContextResolver callerContextResolver;
    private final PermissionsRegistry permissionsRegistry;

    public void handle(final String resourceId) {
        final CallerContext ctx = callerContextResolver.resolve();
        final PermissionsStrategy strategy = permissionsRegistry.getStrategy(ctx);
        if (strategy == null) {
            throw new ForbiddenException("No strategy found for context: " + ctx);
        }
        strategy.verifyPermissions(resourceId);
    }
}
```

**Example (Filter):**
```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class MetricsFilter extends OncePerRequestFilter {
    private final MetricNameResolver metricNameResolver;
    private final MetricsRecorderRegistry metricsRecorderRegistry;

    @Override
    protected void doFilterInternal(HttpServletRequest request, 
                                    HttpServletResponse response, 
                                    FilterChain filterChain) 
            throws ServletException, IOException {
        final long startMs = System.currentTimeMillis();
        try {
            filterChain.doFilter(request, response);
        } finally {
            final String metricName = metricNameResolver.resolve(request);
            final MetricsRecorder recorder = metricsRecorderRegistry.getRecorder(metricName);
            if (recorder != null) {
                recorder.recordMetrics(System.currentTimeMillis() - startMs, request, response);
            }
        }
    }
}
```

### 2. **Resolver** — Context Determination

**Responsibility:** Determine which strategy to use based on input context.

**Rules:**
- ✅ Reads request/context and returns a discriminator (String, Enum, etc.)
- ✅ Returns `null` when no match (Handler/Filter logs warning)
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

    public String resolve(final HttpServletRequest request) {
        if (request == null || request.getRequestURI() == null) {
            return null;
        }
        final String uri = request.getRequestURI();
        return monitoringConfig.getPatternToMetricNameMap().entrySet().stream()
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
- ✅ Filters strategies by calling `canHandle(discriminator)` on each
- ✅ Returns `null` when no strategy matches
- ✅ **Never** contains if/else or switch on strategy type
- ✅ Is a `@Component`

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class MetricsRecorderRegistry {
    private final List<MetricsRecorder> metricsRecorders;

    public MetricsRecorder getRecorder(final String metricName) {
        return metricsRecorders.stream()
                .filter(r -> r.canHandle(metricName))
                .findFirst()
                .orElse(null);
    }
}
```

### 4. **Strategy Interface** — The Contract

**Responsibility:** Define the contract that all strategies must implement.

**Rules:**
- ✅ Defines the core behavior method (e.g., `recordMetrics`, `verifyPermissions`, `map`)
- ✅ Defines `canHandle(discriminator)` — used by Registry for routing
- ✅ Provides a default `canHandle` implementation when possible
- ✅ Is an `interface` (not an abstract class unless shared state is needed)

```java
public interface MetricsRecorder {
    void recordMetrics(long durationMs, HttpServletRequest request, HttpServletResponse response);
    String getSupportedMetricName();

    default boolean canHandle(final String metricName) {
        return StringUtils.isNotBlank(getSupportedMetricName())
                && StringUtils.isNotBlank(metricName)
                && getSupportedMetricName().equals(metricName);
    }
}
```

### 5. **Concrete Strategies** — Implementations

**Responsibility:** Implement the behavior for a specific use case.

**Rules:**
- ✅ Each strategy is a `@Component`
- ✅ Implements the Strategy interface
- ✅ Returns its discriminator value via `getSupportedXxx()` or `supportedContexts()`
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
- ✅ Swallows exceptions with `log.error` and returns sentinel
- ✅ Method naming: `parse<Concept>(request|response|...)`

```java
@Component
@Slf4j
public class ClientIdParser {
    private static final String AZP = "azp";

    public String parseClientId() {
        try {
            final Authentication auth = SecurityContextHolder.getContext().getAuthentication();
            if (auth instanceof JwtToken jwt
                    && jwt.getTokenAttributes() != null
                    && jwt.getTokenAttributes().get(AZP) != null) {
                return String.valueOf(jwt.getTokenAttributes().get(AZP));
            }
            if (auth instanceof BasicAuthenticationToken) {
                return MonitoringConstants.BASIC;
            }
        } catch (final Exception e) {
            log.error("Failed to extract clientId", e);
        }
        return MonitoringConstants.UNKNOWN;
    }
}
```

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
            Tag.of("clientId", clientIdParser.parseClientId())
        );
    }
}
```

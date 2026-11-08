# Request Metrics Skill — Config, constants, filter and name resolver

Part of the [`request-metrics`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 2. `MonitoringConfig` — URI pattern → metric name map

Maps compiled `Pattern` objects to metric name strings. This is the only place
where URI shapes are coupled to metric names; everything else stays generic.

```java
@Configuration
public class MonitoringConfig {

    // Add one entry per metered endpoint or endpoint group — MOST SPECIFIC FIRST (the resolver takes the first match).
    // Key: compiled regex matching the request path inside the application (the servlet context path is stripped).
    // Value: the metric name string passed to MetricsRecorder.getSupportedMetricName().
    private static final List<Map.Entry<Pattern, String>> PATTERN_TO_METRIC_NAME = List.of(
        Map.entry(Pattern.compile("/api/v1/invoices/[^/]+/export"), MonitoringConstants.METRIC_EXPORT_INVOICE),
        Map.entry(Pattern.compile("/api/v1/reports"),                MonitoringConstants.METRIC_GENERATE_REPORT)
    );

    public List<Map.Entry<Pattern, String>> patternToMetricName() {
        return PATTERN_TO_METRIC_NAME;
    }
}
```

Rules:
- Patterns are compiled once at startup (in the static initializer) —
  never compile regexes per-request.
- **Order matters.** Use an ordered `List` of entries, never `Map.of` (unspecified iteration order): with overlapping
  regexes the first match wins, so list the most specific pattern first (same rule as `strategy-registry-pattern`).
- Metric name strings must match exactly the string returned by the
  corresponding `MetricsRecorder.getSupportedMetricName()`.
- URIs not matched by any pattern produce `Optional.empty()`; the filter
  skips recording **silently** (most endpoints have no domain metric — a WARN per request would flood the logs).
  It logs a WARN only when a name resolves but no recorder handles it, which is a wiring bug.
- All metric name strings live as constants in `MonitoringConstants`.

## 3. `MonitoringConstants` — tag names and sentinel values

```java
@NoArgsConstructor(access = AccessLevel.PRIVATE)
public final class MonitoringConstants {
    // Tag names (used in MetricsTagsHelper and individual recorders)
    public static final String METRIC_TAG_REQUEST_METHOD  = "requestMethod";
    public static final String METRIC_TAG_RESPONSE_STATUS = "responseStatus";
    public static final String METRIC_TAG_CLIENT_ID       = "clientId";

    // Sentinel values for when a tag cannot be resolved
    public static final String UNKNOWN = "UNKNOWN";
    public static final String OTHER = "OTHER";     // a caller-supplied value outside the known set
    public static final String BASIC   = "BASIC";    // for Basic-auth clients

    // Metric names — must match MetricsRecorder.getSupportedMetricName() values
    // Convention: <service>.<resource>.<verb>  (replace with your service name)
    public static final String METRIC_PROCESS_ORDER   = "myservice.orders.process";
    public static final String METRIC_EXPORT_INVOICE   = "myservice.invoices.export";
    public static final String METRIC_GENERATE_REPORT = "myservice.reports.generate";
}
```

Rules:
- Every tag name and every metric name string lives here — never inline.
- Sentinel values (`UNKNOWN`, `OTHER`, `BASIC`) ensure tags are never blank. Prometheus treats an empty label value
  as "label absent", so a blank tag merges unrelated requests into one ambiguous series; an explicit sentinel keeps
  "could not resolve" visible and queryable.

## 4. `MetricsFilter` — the single measurement point

```java
@Component
@Slf4j
@RequiredArgsConstructor
@Order(SecurityProperties.DEFAULT_FILTER_ORDER - 1)   // before Spring Security, so 401/403 rejections are recorded too
public class MetricsFilter extends OncePerRequestFilter {

    private final MetricNameResolver metricNameResolver;
    private final MetricsRecorderRegistry metricsRecorderRegistry;

    @Override
    protected boolean shouldNotFilter(@NonNull final HttpServletRequest request) {
        // Skip Spring Boot Actuator paths — they have their own metrics
        return request.getRequestURI() == null
                || request.getRequestURI().startsWith(request.getContextPath() + "/actuator");
    }

    @Override
    protected void doFilterInternal(@NonNull final HttpServletRequest request,
                                    @NonNull final HttpServletResponse response,
                                    @NonNull final FilterChain filterChain)
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
            // always runs — even if the handler throws
            if (request.isAsyncStarted()) {
                // DeferredResult / CompletableFuture: the response is not finished yet — record when it completes
                request.getAsyncContext().addListener(new OnCompleteListener(() -> record(request, response, startNanos)));
            } else {
                record(request, response, startNanos);
            }
        }
    }

    private void record(final HttpServletRequest request, final HttpServletResponse response, final long startNanos) {
        try {
            final long durationMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startNanos);
            metricNameResolver.resolve(request).ifPresent(metricName ->      // no metric for this URI → silently skip
                    metricsRecorderRegistry.getRecorder(metricName).ifPresentOrElse(
                            recorder -> recorder.recordMetrics(durationMs, request, response),
                            () -> log.warn("No recorder found for metric '{}'", metricName)));   // wiring bug
        } catch (final RuntimeException e) {
            // an exception thrown from `finally` would replace the handler's own result (or turn a 200 into a 500)
            log.error("Failed to record metrics for URI {}", request.getRequestURI(), e);
        }
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

Rules:
- **`try/finally`** is mandatory — failed requests must still be recorded.
- Recording must **never** fail the request: catch `RuntimeException` inside the `finally` and log it.
- The filter records elapsed time in milliseconds from before
  `filterChain.doFilter` to after (including exception handling by the MVC
  exception resolver), measured with `System.nanoTime()` (monotonic).
- An exception that escapes the chain is recorded with status **500**, not the response's default 200.
- Async requests (`DeferredResult`, `Callable`, `CompletableFuture`) are recorded once, when the async request
  completes (an `AsyncListener`); `OncePerRequestFilter` skips the async re-dispatch by default.
- **Filter order.** `@Order(SecurityProperties.DEFAULT_FILTER_ORDER - 1)` runs the filter **before** Spring Security,
  so requests rejected with 401/403 are recorded too. A `@Component` filter without `@Order` would run after the
  security chain and never see them. The outer request carries no principal, so the client id is captured inside the
  chain by `ClientIdCaptureInterceptor` ([`parsers-and-helpers.md`](./parsers-and-helpers.md) §6).
- `shouldNotFilter` must skip paths under `<context-path>/actuator` — they expose their own
  Micrometer metrics and would pollute domain counters.
- The filter has **no knowledge of metric names or tag logic** — those live
  in the resolver and recorders.

## 5. `MetricNameResolver` — URI → metric name

```java
@Component
@RequiredArgsConstructor
public class MetricNameResolver {

    private final MonitoringConfig monitoringConfig;

    public Optional<String> resolve(final HttpServletRequest request) {
        if (request == null || request.getRequestURI() == null) {
            return Optional.empty();
        }
        // getRequestURI() includes server.servlet.context-path; the patterns are written without it
        final String uri = request.getRequestURI().substring(request.getContextPath().length());
        return monitoringConfig.patternToMetricName().stream()      // ordered list: most specific pattern first
                .filter(entry -> entry.getKey().matcher(uri).matches())
                .map(Map.Entry::getValue)
                .findFirst();    // empty → no domain metric for this URI; the filter skips it silently
    }
}
```

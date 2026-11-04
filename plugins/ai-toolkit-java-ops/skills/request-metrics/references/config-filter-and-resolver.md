# Request Metrics Skill — Config, constants, filter and name resolver

Part of the [`request-metrics`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 2. `MonitoringConfig` — URI pattern → metric name map

Maps compiled `Pattern` objects to metric name strings. This is the only place
where URI shapes are coupled to metric names; everything else stays generic.

```java
@Getter
@Configuration
public class MonitoringConfig {

    // Add one entry per metered endpoint or endpoint group.
    // Key: compiled regex matching the full request URI.
    // Value: the metric name string passed to MetricsRecorder.getSupportedMetricName().
    private final Map<Pattern, String> patternToMetricNameMap = Map.of(
        Pattern.compile("/api/v1/invoices/[^/]+/export"), MonitoringConstants.METRIC_EXPORT_INVOICE,
        Pattern.compile("/api/v1/reports"),                MonitoringConstants.METRIC_GENERATE_REPORT
    );
}
```

Rules:
- Patterns are compiled once at startup (`Map.of` in the field initializer) —
  never compile regexes per-request.
- Metric name strings must match exactly the string returned by the
  corresponding `MetricsRecorder.getSupportedMetricName()`.
- URIs not matched by any pattern produce a `null` metric name; the filter
  logs a warning and skips recording.
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
- Sentinel values (`UNKNOWN`, `BASIC`) ensure tags are never blank; Prometheus
  rejects metrics with blank label values.

## 4. `MetricsFilter` — the single measurement point

```java
@Component
@Slf4j
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class MetricsFilter extends OncePerRequestFilter {

    private final MetricNameResolver metricNameResolver;
    private final MetricsRecorderRegistry metricsRecorderRegistry;

    @Override
    protected boolean shouldNotFilter(@NotNull final HttpServletRequest request) {
        // Skip Spring Boot Actuator paths — they have their own metrics
        return request.getRequestURI() == null
                || request.getRequestURI().contains("actuator");
    }

    @Override
    protected void doFilterInternal(@NotNull final HttpServletRequest request,
                                    @NotNull final HttpServletResponse response,
                                    final FilterChain filterChain)
            throws ServletException, IOException {
        final long startMs = System.currentTimeMillis();
        try {
            filterChain.doFilter(request, response);
        } finally {
            // always runs — even if the handler throws
            final String metricName = metricNameResolver.resolve(request);
            final MetricsRecorder recorder = metricsRecorderRegistry.getMetricsRecorder(metricName);
            if (recorder == null) {
                log.warn("No recorder found for metric '{}' (URI: {})",
                        metricName, request.getRequestURI());
            } else {
                recorder.recordMetrics(System.currentTimeMillis() - startMs, request, response);
            }
        }
    }
}
```

Rules:
- **`try/finally`** is mandatory — failed requests must still be recorded.
- The filter records elapsed time in milliseconds from before
  `filterChain.doFilter` to after (including exception handling by the MVC
  exception resolver).
- `shouldNotFilter` must skip `actuator` paths — they expose their own
  Micrometer metrics and would pollute domain counters.
- The filter has **no knowledge of metric names or tag logic** — those live
  in the resolver and recorders.

## 5. `MetricNameResolver` — URI → metric name

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
                .orElse(null);    // null → filter logs a warning, skips recording
    }
}
```

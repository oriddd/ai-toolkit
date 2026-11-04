# Request Metrics Skill — Recorders and registry

Part of the [`request-metrics`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 9. `MetricsRecorder` — the interface

```java
public interface MetricsRecorder {

    /**
     * Called by MetricsFilter after the request completes.
     * @param durationMs  elapsed milliseconds (filter measured)
     * @param request     the completed HTTP request
     * @param response    the completed HTTP response
     */
    void recordMetrics(long durationMs, HttpServletRequest request,
                       HttpServletResponse response);

    /**
     * The metric name this recorder handles.
     * Must exactly match the value in MonitoringConfig's pattern map.
     */
    String getSupportedMetricName();

    /**
     * Default routing check used by MetricsRecorderRegistry.
     * Override only to add composite matching logic.
     */
    default boolean canHandle(final String metricName) {
        return StringUtils.isNotBlank(getSupportedMetricName())
                && StringUtils.isNotBlank(metricName)
                && getSupportedMetricName().equals(metricName);
    }
}
```

## 10. `MetricsRecorderRegistry` — Strategy + Registry routing

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class MetricsRecorderRegistry {

    // Spring injects ALL MetricsRecorder beans automatically
    private final List<MetricsRecorder> metricsRecorders;

    public MetricsRecorder getMetricsRecorder(final String metricName) {
        return metricsRecorders.stream()
                .filter(r -> r.canHandle(metricName))
                .findFirst()
                .orElse(null);
    }
}
```

Spring auto-discovers every `@Component` that implements `MetricsRecorder` via
the `List<MetricsRecorder>` constructor injection. Adding a new recorder is
purely additive — zero changes to the registry or filter.

## 11. Adding a use-case recorder (the only change needed for a new metric)

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
@Slf4j
public class ExportInvoiceMetricsRecorder implements MetricsRecorder {

    private final MetricsTimerHelper metricsTimerHelper;
    private final ExportFormatParser exportFormatParser;   // domain-specific tag

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
        log.debug("Recorded metric '{}' for URI '{}' in {}ms",
                getSupportedMetricName(), request.getRequestURI(), durationMs);
    }
}
```

Also add the URI pattern entry in `MonitoringConfig.patternToMetricNameMap` and
the metric name constant in `MonitoringConstants`.

**Checklist for a new metric:**
- [ ] Add a `public static final String METRIC_<NAME>` constant to `MonitoringConstants`.
- [ ] Add a `Pattern.compile(...)` → `METRIC_<NAME>` entry to `MonitoringConfig.patternToMetricNameMap`.
- [ ] Add a new `<UseCase>MetricsRecorder implements MetricsRecorder` in `recorder/`.
- [ ] If a new domain tag is needed, add a `<Concept>Parser` in `parser/`.
- [ ] Unit-test the recorder and any new parser.

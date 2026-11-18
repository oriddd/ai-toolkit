# Request Metrics Skill — Recorders and registry

Part of the [`request-metrics`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 9. `MetricsRecorder` — the interface

```java
public interface MetricsRecorder {

    /**
     * Called by MetricsFilter once the request (including any async dispatch) has completed. The request and response
     * are passed through to parsers and MetricsTimerHelper; the recorder never reads them itself.
     */
    void recordMetrics(long durationMs, HttpServletRequest request,
                       HttpServletResponse response);

    /** Must exactly match the value in MonitoringConfig's pattern map. */
    String getSupportedMetricName();

    /** Override only to add composite matching logic. String::isBlank — no commons-lang3 needed. */
    default boolean canHandle(final @Nullable String metricName) {
        return metricName != null && !metricName.isBlank() && metricName.equals(getSupportedMetricName());
    }
}
```

## 10. `MetricsRecorderRegistry` — Strategy + Registry routing

```java
@Component
public class MetricsRecorderRegistry {

    private final List<MetricsRecorder> metricsRecorders;

    // Spring injects ALL MetricsRecorder beans automatically; fail fast when two declare the same metric name
    public MetricsRecorderRegistry(final List<MetricsRecorder> metricsRecorders) {
        final Map<String, MetricsRecorder> declared = new HashMap<>();
        for (final MetricsRecorder recorder : metricsRecorders) {
            final MetricsRecorder first = declared.putIfAbsent(recorder.getSupportedMetricName(), recorder);
            if (first != null) {
                throw new IllegalStateException("Two recorders for metric '" + recorder.getSupportedMetricName() + "': "
                        + first.getClass().getName() + ", " + recorder.getClass().getName());
            }
        }
        this.metricsRecorders = List.copyOf(metricsRecorders);
    }

    public @Nullable MetricsRecorder getRecorder(final @Nullable String metricName) {
        return metricsRecorders.stream()
                .filter(recorder -> recorder.canHandle(metricName))
                .findFirst()
                .orElse(null);
    }
}
```

Spring auto-discovers every `@Component` that implements `MetricsRecorder` via
the `List<MetricsRecorder>` constructor injection. Adding a new recorder is
purely additive — zero changes to the registry or filter. The registry routes by `canHandle(metricName)`; two
recorders declaring the same metric name fail the application at startup (routing must never depend on bean order),
and a missing recorder is a `null` from the `@Nullable` `getRecorder` (`strategy-registry-pattern`).

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
        log.debug("Recorded metric '{}' in {}ms", getSupportedMetricName(), durationMs);
    }
}
```

Also add the URI pattern entry in `MonitoringConfig.PATTERN_TO_METRIC_NAME` and
the metric name constant in `MonitoringConstants`.

**Checklist for a new metric:**
- [ ] Add a `public static final String METRIC_<NAME>` constant to `MonitoringConstants`.
- [ ] Add a `Pattern.compile(...)` → `METRIC_<NAME>` entry to `MonitoringConfig.PATTERN_TO_METRIC_NAME` (more specific patterns first).
- [ ] Add a new `<UseCase>MetricsRecorder implements MetricsRecorder` in `recorder/`.
- [ ] If a new domain tag is needed, add a `<Concept>Parser` in `parser/`.
- [ ] Unit-test the recorder and any new parser.

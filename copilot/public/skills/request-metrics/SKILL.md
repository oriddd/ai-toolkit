---
name: request-metrics
description: Implement per-request domain metrics in a Spring Boot microservice using the canonical Filter + Recorder + Parser pattern. A single OncePerRequestFilter measures elapsed time for every request, resolves the metric name from a URI-pattern map, delegates to a use-case-specific MetricsRecorder (Strategy + Registry), and emits a Micrometer Timer with structured tags extracted by pluggable parsers (HTTP method, response status, authenticated client ID, and any domain-specific tag). Add new use-case metrics by adding one new MetricsRecorder — the filter and registry never change. Apply whenever a new timed, domain-meaningful endpoint metric is needed.
tier: must
applies_to: [rest, monolith]
depends_on: [code-structure, observability, spring-boot-conventions]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-07-05
---

# Request Metrics Skill (public)

Domain metrics in a Spring Boot service live in a dedicated `monitor/` package
that follows the **Filter → Recorder → Parser** pattern. A single filter
measures every request; a registry routes to the right recorder; parsers extract
structured tags. Adding a metric for a new endpoint requires adding exactly
**one new `MetricsRecorder` class** — the filter, registry, and parsers never
change. This is the open/closed principle (OCP) applied to observability.

> This skill is the concrete implementation of Pattern B described in
> `code-structure` §3. `observability` covers the three-pillar platform setup
> (Micrometer, structured logs, OpenTelemetry). This skill covers domain-level
> per-request metrics on top of that foundation.

## 1. Package structure

```
monitor/
├── MetricsFilter.java              # OncePerRequestFilter — measures latency, delegates to recorder
├── MetricsTagsHelper.java          # assembles the generic tag set for any recorder
├── MetricsTimerHelper.java         # builds a Micrometer Timer with custom SLO buckets
├── MonitoringConfig.java           # @Configuration: URI regex Pattern → metric name map
├── MonitoringConstants.java        # tag name constants + sentinel values (UNKNOWN, BASIC, …)
├── parser/
│   ├── MetricNameResolver.java     # resolves metric name from URI using MonitoringConfig
│   ├── RequestMethodParser.java    # extracts HTTP method tag
│   ├── ResponseStatusParser.java   # extracts HTTP status tag
│   ├── ClientIdParser.java         # extracts authenticated client ID tag
│   └── <Domain>Parser.java         # one per additional domain tag (targetFormat, caseType, …)
└── recorder/
    ├── MetricsRecorder.java         # interface: recordMetrics + getSupportedMetricName + canHandle
    ├── MetricsRecorderRegistry.java # injects List<MetricsRecorder>, routes by metric name
    └── <UseCase>MetricsRecorder.java  # one per business use case that needs a metric
```

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
        Pattern.compile("/api/v1/entities/[^/]+/convert"), MonitoringConstants.METRIC_CONVERT_ENTITY,
        Pattern.compile("/api/v1/reports"),                MonitoringConstants.METRIC_CREATE_REPORT
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
    public static final String METRIC_PROCESS_ORDER  = "myservice.orders.process";
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

## 6. Parsers — one per extractable tag

Each parser is a focused `@Component` that extracts exactly one tag value from
the request/response context. Parsers always return a non-blank sentinel
(`UNKNOWN`, `BASIC`, …) on failure — never `null` or empty string, because
Prometheus rejects blank label values.

### `RequestMethodParser`

```java
@Component
public class RequestMethodParser {
    public String parseRequestMethod(final HttpServletRequest request) {
        if (request == null || request.getMethod() == null) {
            return MonitoringConstants.UNKNOWN;
        }
        return request.getMethod();
    }
}
```

### `ResponseStatusParser`

```java
@Component
public class ResponseStatusParser {
    public String parseResponseStatus(final HttpServletResponse response) {
        return response == null
                ? MonitoringConstants.UNKNOWN
                : String.valueOf(response.getStatus());
    }
}
```

### `ClientIdParser` — auth-aware tag extraction

```java
@Component
@Slf4j
public class ClientIdParser {
    private static final String AZP = "azp";   // JWT authorized party claim

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
            log.error("Failed to extract clientId for metrics tag", e);
        }
        return MonitoringConstants.UNKNOWN;
    }
}
```

### Adding a domain-specific parser

One parser per additional tag (e.g. target format, case type):

```java
@Component
public class TargetFormatParser {
    public String parseTargetFormat(final HttpServletRequest request) {
        final String format = request.getParameter("targetFormat");
        return StringUtils.isBlank(format) ? MonitoringConstants.UNKNOWN : format;
    }
}
```

Rules for all parsers:
- **Never return `null` or `""`** — always return a non-blank sentinel.
- **Swallow exceptions** with a `log.error` and return the sentinel; a bad tag
  must not fail the request.
- Keep the method name `parse<TagConcept>(request|response|…)` for consistency.

## 7. `MetricsTagsHelper` — generic tag set

Assembles the tags that apply to **every** recorder, keeping individual
recorders DRY:

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
            Tag.of(MonitoringConstants.METRIC_TAG_REQUEST_METHOD,
                   requestMethodParser.parseRequestMethod(request)),
            Tag.of(MonitoringConstants.METRIC_TAG_RESPONSE_STATUS,
                   responseStatusParser.parseResponseStatus(response)),
            Tag.of(MonitoringConstants.METRIC_TAG_CLIENT_ID,
                   clientIdParser.parseClientId())
        );
    }
}
```

Recorders call `metricsTagsHelper.buildGenericTags(request, response)` and
then add their own domain-specific tags on top.

## 8. `MetricsTimerHelper` — Timer with custom SLO buckets

Builds a `Timer` with custom Service Level Objective (SLO) histogram buckets —
defined once so all recorders use consistent latency buckets:

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class MetricsTimerHelper {
    private final MeterRegistry meterRegistry;
    private final MetricsTagsHelper metricsTagsHelper;

    // SLO buckets in seconds (Micrometer Timer SLOs are Duration-based)
    private static final double[] SLO_SECONDS = {0.1, 0.15, 0.2, 0.3, 0.4, 0.5, 0.75, 1.0, 2.0};
    private static final Duration[] SLO_DURATIONS = Arrays.stream(SLO_SECONDS)
            .mapToObj(s -> Duration.ofMillis((long) (s * 1000)))
            .toArray(Duration[]::new);

    public Timer buildGenericTimer(final String metricName,
                                   final HttpServletRequest request,
                                   final HttpServletResponse response) {
        return Timer.builder(metricName)
                .tags(metricsTagsHelper.buildGenericTags(request, response))
                .publishPercentileHistogram(false)
                .serviceLevelObjectives(SLO_DURATIONS)
                .register(meterRegistry);
    }

    public Timer buildTimerWithExtraTags(final String metricName,
                                         final HttpServletRequest request,
                                         final HttpServletResponse response,
                                         final Tag... extraTags) {
        final Set<Tag> tags = new HashSet<>(
                metricsTagsHelper.buildGenericTags(request, response));
        tags.addAll(Arrays.asList(extraTags));
        return Timer.builder(metricName)
                .tags(tags)
                .publishPercentileHistogram(false)
                .serviceLevelObjectives(SLO_DURATIONS)
                .register(meterRegistry);
    }
}
```

Rules:
- **SLO buckets are defined once here** — recorders call `MetricsTimerHelper`,
  not `Timer.builder(...)` directly.
- `publishPercentileHistogram(false)` — use SLO buckets instead of full
  percentile histogram to control Prometheus cardinality.
- If a recorder needs extra domain tags, use `buildTimerWithExtraTags(...)`.

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
public class ConvertEntityMetricsRecorder implements MetricsRecorder {

    private final MetricsTimerHelper metricsTimerHelper;
    private final TargetFormatParser targetFormatParser;   // domain-specific tag

    @Override
    public String getSupportedMetricName() {
        return MonitoringConstants.METRIC_CONVERT_ENTITY;
    }

    @Override
    public void recordMetrics(final long durationMs,
                              final HttpServletRequest request,
                              final HttpServletResponse response) {
        final Tag targetFormatTag = Tag.of("targetFormat",
                targetFormatParser.parseTargetFormat(request));

        final Timer timer = metricsTimerHelper.buildTimerWithExtraTags(
                getSupportedMetricName(), request, response, targetFormatTag);

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

## 12. Testing

### Testing a parser

```java
class ResponseStatusParserTest {
    private final ResponseStatusParser parser = new ResponseStatusParser();

    @Test
    void nullResponse_returnsUnknown() {
        assertThat(parser.parseResponseStatus(null)).isEqualTo(MonitoringConstants.UNKNOWN);
    }

    @Test
    void validResponse_returnsStatusString() {
        final HttpServletResponse response = mock(HttpServletResponse.class);
        when(response.getStatus()).thenReturn(200);
        assertThat(parser.parseResponseStatus(response)).isEqualTo("200");
    }
}
```

### Testing a recorder

```java
class ConvertEntityMetricsRecorderTest {
    private final MetricsTimerHelper timerHelper = mock(MetricsTimerHelper.class);
    private final TargetFormatParser formatParser = mock(TargetFormatParser.class);
    private final ConvertEntityMetricsRecorder recorder =
            new ConvertEntityMetricsRecorder(timerHelper, formatParser);

    @Test
    void canHandle_matchingMetricName_returnsTrue() {
        assertThat(recorder.canHandle(MonitoringConstants.METRIC_CONVERT_ENTITY)).isTrue();
    }

    @Test
    void canHandle_differentMetricName_returnsFalse() {
        assertThat(recorder.canHandle("other.metric")).isFalse();
    }

    @Test
    void recordMetrics_buildsTimerAndRecords() {
        final HttpServletRequest req = mock(HttpServletRequest.class);
        final HttpServletResponse res = mock(HttpServletResponse.class);
        final Timer timer = mock(Timer.class);

        when(formatParser.parseTargetFormat(req)).thenReturn("pdf");
        when(timerHelper.buildTimerWithExtraTags(any(), eq(req), eq(res), any()))
                .thenReturn(timer);

        recorder.recordMetrics(123L, req, res);

        verify(timer).record(123L, TimeUnit.MILLISECONDS);
    }
}
```

### Testing the filter

```java
@ExtendWith(MockitoExtension.class)
class MetricsFilterTest {
    @Mock MetricNameResolver resolver;
    @Mock MetricsRecorderRegistry registry;
    @Mock MetricsRecorder recorder;
    @Mock FilterChain chain;
    @Mock HttpServletRequest request;
    @Mock HttpServletResponse response;

    @InjectMocks MetricsFilter filter;

    @Test
    void doFilter_recorderFound_callsRecord() throws Exception {
        when(request.getRequestURI()).thenReturn("/api/v1/entities/e1/convert");
        when(resolver.resolve(request)).thenReturn(MonitoringConstants.METRIC_CONVERT_ENTITY);
        when(registry.getMetricsRecorder(MonitoringConstants.METRIC_CONVERT_ENTITY))
                .thenReturn(recorder);

        filter.doFilterInternal(request, response, chain);

        verify(chain).doFilter(request, response);
        verify(recorder).recordMetrics(anyLong(), eq(request), eq(response));
    }

    @Test
    void doFilter_chainThrows_recorderStillCalled() throws Exception {
        when(request.getRequestURI()).thenReturn("/api/v1/entities/e1/convert");
        when(resolver.resolve(request)).thenReturn(MonitoringConstants.METRIC_CONVERT_ENTITY);
        when(registry.getMetricsRecorder(any())).thenReturn(recorder);
        doThrow(new ServletException("boom")).when(chain).doFilter(any(), any());

        assertThrows(ServletException.class,
                () -> filter.doFilterInternal(request, response, chain));
        verify(recorder).recordMetrics(anyLong(), eq(request), eq(response));
    }
}
```

## Do / Don't

✅ Add a new metric by adding **one** `MetricsRecorder` + one entry in
   `MonitoringConfig` — never touch the filter or registry.
✅ All parsers return a non-blank sentinel on failure — never `null` or `""`.
✅ SLO histogram buckets are defined once in `MetricsTimerHelper` and reused
   by all recorders.
✅ Measure elapsed time in the filter's `try/finally` — failed requests must
   also be recorded.
✅ Skip `actuator` URIs in `shouldNotFilter` — they have their own metrics.
✅ Tag names live in `MonitoringConstants` — never inline strings.
❌ Never read `SecurityContextHolder` or `HttpServletRequest` inside a
   `MetricsRecorder` — extract that in a parser and pass the result.
❌ Never compile regex patterns per-request — compile once in `MonitoringConfig`.
❌ Never emit a blank tag value — Prometheus silently drops or rejects them.
❌ Never add business logic to `MetricsFilter` — it only measures, routes, and
   delegates.

## Cross-references

- [`observability`](../observability/SKILL.md) — three-pillar platform setup
  (Micrometer registry, structured logs, OpenTelemetry); this skill adds
  domain-level per-request metrics on top.
- [`code-structure`](../code-structure/SKILL.md) §3 — Pattern B overview that
  this skill fully expands.
- [`unit-tests`](../unit-tests/SKILL.md) — parser and recorder unit-test shapes.
- [`spring-boot-conventions`](../spring-boot-conventions/SKILL.md) — typed
  `@ConfigurationProperties` if `MonitoringConfig` grows beyond a `Map.of`.


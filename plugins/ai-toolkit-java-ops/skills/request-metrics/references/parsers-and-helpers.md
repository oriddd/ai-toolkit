# Request Metrics Skill — Parsers and helpers

Part of the [`request-metrics`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

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

    // Reads the principal from the request, never SecurityContextHolder (that stays in permission/,
    // ArchUnit rule securityHolderLivesInPermissionOnly). Spring Security's request wrapper returns
    // the current Authentication from getUserPrincipal().
    public String parseClientId(final HttpServletRequest request) {
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
        } catch (final Exception e) {
            log.error("Failed to extract clientId for metrics tag", e);
        }
        return MonitoringConstants.UNKNOWN;
    }
}
```

### Adding a domain-specific parser

One parser per additional tag (e.g. export format, order type):

```java
@Component
public class ExportFormatParser {
    private static final Set<String> KNOWN_FORMATS = Set.of("csv", "pdf", "xlsx");

    public String parseExportFormat(final HttpServletRequest request) {
        final String format = request.getParameter("format");
        if (StringUtils.isBlank(format)) {
            return MonitoringConstants.UNKNOWN;
        }
        // the value is caller-controlled: map it onto a closed set, never use it as a tag as-is
        return KNOWN_FORMATS.contains(format.toLowerCase(Locale.ROOT)) ? format.toLowerCase(Locale.ROOT) : MonitoringConstants.OTHER;
    }
}
```

Rules for all parsers:
- **Never return `null` or `""`** — always return a non-blank sentinel.
- **Tag values come from a closed set.** Never return a request parameter, header or path segment as-is: a client could
  create unlimited time series. Map it onto known values and return `OTHER` for the rest (`observability`: fewer than 100 values per tag).
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
                   clientIdParser.parseClientId(request))
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

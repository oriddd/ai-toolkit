# Request Metrics Skill — Parsers and helpers

Part of the [`request-metrics`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 6. Parsers — one per extractable tag

Each parser is a focused `@Component` that extracts exactly one tag value from
the request/response context. Parsers always return a non-blank sentinel
(`UNKNOWN`, `BASIC`, …) on failure — never `null` or empty string. Micrometer rejects a `null` tag value, and
Prometheus treats an empty label value as "label absent", which merges unrelated requests into one ambiguous series.
A parser that accepts a missing request/response declares the parameter `@Nullable` (JSpecify, the `static-analysis`
NullAway convention); otherwise NullAway rejects the `parse…(null)` call in its unit test.

### `RequestMethodParser`

```java
@Component
public class RequestMethodParser {
    public String parseRequestMethod(final @Nullable HttpServletRequest request) {
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
    public String parseResponseStatus(final @Nullable HttpServletResponse response) {
        return response == null
                ? MonitoringConstants.UNKNOWN
                : String.valueOf(response.getStatus());
    }
}
```

### `ClientIdParser` — auth-aware tag extraction

Only when the service uses Spring Security (create-repo #9 auth = yes): the parser imports `JwtAuthenticationToken`
(`spring-boot-starter-oauth2-resource-server`) and `UsernamePasswordAuthenticationToken`, which do not exist on the
classpath otherwise. Without authentication there is no client id to read: leave out `ClientIdParser`,
`ClientIdCaptureInterceptor`, its `WebMvcConfigurer` and the `clientId` tag in `MetricsTagsHelper` (§7) — a tag that is
always `UNKNOWN` only adds a label.

```java
@Component
@Slf4j
public class ClientIdParser {
    /** Request attribute holding the client id captured inside the security chain (ClientIdCaptureInterceptor). */
    public static final String CLIENT_ID_ATTRIBUTE = ClientIdParser.class.getName() + ".clientId";
    private static final String AZP = "azp";   // JWT authorized party claim

    // Reads the principal from the request, never SecurityContextHolder (that stays in permission/,
    // ArchUnit rule securityHolderLivesInPermissionOnly). Spring Security's request wrapper returns
    // the current Authentication from getUserPrincipal().
    public String parseClientId(final @Nullable HttpServletRequest request) {
        if (request != null && request.getAttribute(CLIENT_ID_ATTRIBUTE) instanceof String captured) {
            return captured;    // a filter running outside Spring Security sees no principal itself
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
            log.debug("Failed to extract clientId for metrics tag", e);   // DEBUG: a bad token on every call must not flood the logs
        }
        return MonitoringConstants.UNKNOWN;
    }
}
```

When the metrics filter is ordered **before** Spring Security (so 401/403 rejections are recorded), the request it
holds carries no principal. A `HandlerInterceptor` captures the client id while the request is inside the security
chain; request attributes are shared by the wrapped and the outer request. Requests rejected by security never reach
it and are tagged `UNKNOWN`:

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

### Adding a domain-specific parser

One parser per additional tag (e.g. export format, order type):

```java
@Component
public class ExportFormatParser {
    private static final Set<String> KNOWN_FORMATS = Set.of("csv", "pdf", "xlsx");

    public String parseExportFormat(final HttpServletRequest request) {
        final String format = request.getParameter("format");
        if (format == null || format.isBlank()) {   // String::isBlank — no commons-lang3 needed
            return MonitoringConstants.UNKNOWN;
        }
        // the value is caller-controlled: map it onto a closed set, never use it as a tag as-is
        return KNOWN_FORMATS.contains(format.toLowerCase(Locale.ROOT)) ? format.toLowerCase(Locale.ROOT) : MonitoringConstants.OTHER;
    }
}
```

Rules for all parsers:
- **Never return `null` or `""`** — always return a non-blank sentinel.
- A parameter the parser null-checks is `@Nullable` (`org.jspecify.annotations.Nullable`).
- **Tag values come from a closed set.** Never return a request parameter, header or path segment as-is: a client could
  create unlimited time series. Map it onto known values and return `OTHER` for the rest (`observability`: fewer than 100 values per tag).
- **Swallow exceptions** and return the sentinel; a bad tag must not fail the request. Log at `DEBUG` (or a
  rate-limited `WARN` plus a failure counter), never `ERROR` per request — one malformed header on every call would
  flood the logs.
- Keep the method name `parse<TagConcept>(request|response|…)` for consistency.

## 7. `MetricsTagsHelper` — generic tag set

Assembles the tags that apply to **every** recorder, keeping individual
recorders DRY:

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
then add their own domain-specific tags on top. Without Spring Security (§6) the helper has two parsers and two tags.

## 8. `MetricsTimerHelper` — Timer with custom SLO buckets

Builds a `Timer` with custom Service Level Objective (SLO) histogram buckets —
defined once so all recorders use consistent latency buckets:

```java
@Component
@RequiredArgsConstructor
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

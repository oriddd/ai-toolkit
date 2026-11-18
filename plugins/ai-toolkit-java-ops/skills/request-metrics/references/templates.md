# Request Metrics Skill — Shipped templates

Part of the [`request-metrics`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 13. Templates

The whole stack is shipped and rendered into a service by `tools/render-java-proof.sh`, which runs the tests below under
the unit, JaCoCo and PIT gates. Package layout as in SKILL.md §1 (`monitor/`, `monitor/parser/`, `monitor/recorder/`).
The templates differ from the prose snippets only where a gate required it (no dead null checks, two literal URI patterns
instead of one regex with an optional group, which SpotBugs reports as ReDoS).

- Core: [`MonitoringConstants`](../templates/MonitoringConstants.java.tmpl), [`MonitoringConfig`](../templates/MonitoringConfig.java.tmpl), [`MetricsFilter`](../templates/MetricsFilter.java.tmpl), [`MetricsTagsHelper`](../templates/MetricsTagsHelper.java.tmpl), [`MetricsTimerHelper`](../templates/MetricsTimerHelper.java.tmpl), [`ClientIdCaptureInterceptor`](../templates/ClientIdCaptureInterceptor.java.tmpl) + [`MonitoringWebConfig`](../templates/MonitoringWebConfig.java.tmpl).
- Parsers: [`MetricNameResolver`](../templates/MetricNameResolver.java.tmpl), [`RequestMethodParser`](../templates/RequestMethodParser.java.tmpl), [`ResponseStatusParser`](../templates/ResponseStatusParser.java.tmpl), [`ClientIdParser`](../templates/ClientIdParser.java.tmpl) (needs `spring-boot-starter-oauth2-resource-server`), [`ExportFormatParser`](../templates/ExportFormatParser.java.tmpl).
- Recorders: [`MetricsRecorder`](../templates/MetricsRecorder.java.tmpl), [`MetricsRecorderRegistry`](../templates/MetricsRecorderRegistry.java.tmpl), example [`InvoiceMetricsRecorder`](../templates/InvoiceMetricsRecorder.java.tmpl) (timer `orders.invoices.requests`, tags `requestMethod`, `responseStatus`, `clientId`, `format`). Rename the example metric, pattern and recorder for each use case.
- Tests: [`ParsersTest`](../templates/ParsersTest.java.tmpl), [`MetricNameResolverTest`](../templates/MetricNameResolverTest.java.tmpl), [`MetricsFilterTest`](../templates/MetricsFilterTest.java.tmpl) (500 on an escaped exception, async completion, recording failures swallowed), [`MetricsStackTest`](../templates/MetricsStackTest.java.tmpl) (`SimpleMeterRegistry`: Timer name, tags, SLO buckets, duplicate recorders refused).
- Component and slice tests: [`RequestMetricsComponentTest`](../templates/RequestMetricsComponentTest.java.tmpl) (full context, `@AutoConfigureObservability`, asserts the Timer name and the camelCase tags on the real `MeterRegistry`) and [`RequestMetricsSecurityTest`](../templates/RequestMetricsSecurityTest.java.tmpl) (production `SecurityConfig`: the `azp` claim becomes the `clientId` tag; a 401 is still recorded because the filter runs before Spring Security).
- Slice tests of other skills (`SecurityTest`, `ProductionSecurityChainTest`, CORS and header tests) mock `MetricNameResolver`, `MetricsRecorderRegistry` and `ClientIdParser` because the filter, the interceptor and the web configurer are part of every `@WebMvcTest`.

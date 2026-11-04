# Request Metrics Skill — Testing

Part of the [`request-metrics`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

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
class ExportInvoiceMetricsRecorderTest {
    private final MetricsTimerHelper timerHelper = mock(MetricsTimerHelper.class);
    private final ExportFormatParser formatParser = mock(ExportFormatParser.class);
    private final ExportInvoiceMetricsRecorder recorder =
            new ExportInvoiceMetricsRecorder(timerHelper, formatParser);

    @Test
    void canHandle_matchingMetricName_returnsTrue() {
        assertThat(recorder.canHandle(MonitoringConstants.METRIC_EXPORT_INVOICE)).isTrue();
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

        when(formatParser.parseExportFormat(req)).thenReturn("pdf");
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
        when(request.getRequestURI()).thenReturn("/api/v1/invoices/e1/export");
        when(resolver.resolve(request)).thenReturn(MonitoringConstants.METRIC_EXPORT_INVOICE);
        when(registry.getMetricsRecorder(MonitoringConstants.METRIC_EXPORT_INVOICE))
                .thenReturn(recorder);

        filter.doFilterInternal(request, response, chain);

        verify(chain).doFilter(request, response);
        verify(recorder).recordMetrics(anyLong(), eq(request), eq(response));
    }

    @Test
    void doFilter_chainThrows_recorderStillCalled() throws Exception {
        when(request.getRequestURI()).thenReturn("/api/v1/invoices/e1/export");
        when(resolver.resolve(request)).thenReturn(MonitoringConstants.METRIC_EXPORT_INVOICE);
        when(registry.getMetricsRecorder(any())).thenReturn(recorder);
        doThrow(new ServletException("boom")).when(chain).doFilter(any(), any());

        assertThrows(ServletException.class,
                () -> filter.doFilterInternal(request, response, chain));
        verify(recorder).recordMetrics(anyLong(), eq(request), eq(response));
    }
}
```

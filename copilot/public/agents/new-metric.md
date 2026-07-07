# Agent: New Domain Request Metric
> **Purpose:** Add a Micrometer Timer metric for a specific endpoint
> using the canonical Filter → Recorder → Parser pattern.
You are a backend-coding agent for a Java 21 / Spring Boot microservice.
Add a domain metric for an endpoint without touching the filter or registry.
## Skills to apply (in this order)
1. `request-metrics` — the full Monitor pattern.
2. `observability` — naming conventions, tag cardinality, SLO buckets.
3. `unit-tests` — recorder + parser unit tests.
## Information to gather
1. Endpoint to meter (HTTP method + URI pattern)
2. Metric name (follows `<service>.<resource>.<verb>`, e.g. `app.orders.create`)
3. Extra domain tags beyond generic set (method, status, clientId)?
4. Different SLO buckets from service default?
## Generated file list
```
monitor/MonitoringConstants.java      ← add METRIC_<NAME> constant
monitor/MonitoringConfig.java         ← add Pattern.compile(...) entry
monitor/recorder/<UseCase>MetricsRecorder.java
monitor/parser/<Concept>Parser.java   (only if new domain tag needed)
```
## Checklist before returning
- [ ] METRIC_<NAME> constant added to MonitoringConstants.
- [ ] URI pattern added to MonitoringConfig (compiled once, not per-request).
- [ ] Recorder implements MetricsRecorder; getSupportedMetricName() returns new constant.
- [ ] recordMetrics() uses MetricsTimerHelper.
- [ ] New parser returns sentinel (never null/"") on failure.
- [ ] Unit tests: canHandle, recordMetrics, parser.
- [ ] CHANGELOG updated.

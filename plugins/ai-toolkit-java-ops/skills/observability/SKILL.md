---
name: observability
description: >
  Java / Spring Boot observability — Micrometer + Prometheus metrics, JSON logs with MDC correlation IDs,
  OpenTelemetry traces, SLI/SLO conventions. Use when a new service is created or production issues cannot be
  debugged. Per-endpoint timers live in `request-metrics`.
tier: must
applies_to: [rest, event, scheduler, monolith]
depends_on: [code-structure, pluggable-architecture]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Observability Skill
A microservice is only as good as the signals it emits. This skill makes the
three pillars uniform across every service.

## 1. Metrics — Micrometer + Prometheus

Already wired by `spring-boot-starter-actuator` + `micrometer-registry-prometheus`.
Conventions:

Metric names and tag style follow `request-metrics` (guild #24), so every metric in a service looks the same:

- **Naming.** `<service>.<domain>.<verb>` — e.g. `foo.invoices.export`.
  All lowercase + dots; never CamelCase. Also set the common tag
  `management.metrics.tags.application: ${spring.application.name}` so dashboards can filter by service.
- **Tags.** camelCase tag names (`requestMethod`, `responseStatus`, `clientId`, `status` = `success`/`error`, `targetFormat`, `callerType`), names
  kept as constants (`MonitoringConstants`). Keep cardinality bounded: values come from a closed set, with `UNKNOWN` /
  `OTHER` sentinels. **Never** a free-form id, URL, or message. `clientId` is allowed because it is the OAuth client
  (`azp`) — a small, registered set of callers — never an end-user id.
- **Types.** `Counter` for events; `Timer` for latencies (records count +
  histogram); `Gauge` for current values (queue depth, pool size).
- **Use the Filter + Recorder Registry pattern** from `request-metrics` so
  business metrics are added by *new classes*, never by editing the filter.

```java
meterRegistry.timer("foo.invoices.export",
        "sourceFormat", src, "targetFormat", tgt, "status", "success")
    .record(elapsed);
```

## 2. Structured JSON logs + MDC

Use **Logback with `logstash-logback-encoder`** or `logback-spring.xml` with
the `LogstashEncoder` so logs are one JSON object per line — directly
indexable by Elastic / Loki / Datadog without a parser.

On **Spring Boot 3.4+** prefer the native structured logging instead — no extra
dependency, MDC keys are included automatically:

```yaml
logging.structured.format.console: logstash   # or ecs / gelf
```

Use `logstash-logback-encoder` (below) on older Boot versions or when you need
its extra encoder options.

```xml
<dependency>
    <groupId>net.logstash.logback</groupId>
    <artifactId>logstash-logback-encoder</artifactId>
    <version>8.0</version>   <!-- 8.x is the line for Logback 1.5 (Boot 3.4+); let Renovate bump it -->
</dependency>
```

`logback-spring.xml` (excerpt):

```xml
<appender name="JSON" class="ch.qos.logback.core.ConsoleAppender">
    <encoder class="net.logstash.logback.encoder.LogstashEncoder">
        <includeMdcKeyName>traceId</includeMdcKeyName>
        <includeMdcKeyName>spanId</includeMdcKeyName>
        <includeMdcKeyName>callerId</includeMdcKeyName>
    </encoder>
</appender>
```

**MDC propagation rules.**
- Put `callerId` (and other request-scoped keys) into MDC at the request boundary
  (`OncePerRequestFilter`), clear them in `finally`. `traceId` / `spanId` are put
  into MDC by Micrometer Tracing (§3) — do not set them by hand.
- For `@Async` / `CompletableFuture`, decorate the executor with Spring's
  `ContextPropagatingTaskDecorator` (Spring Framework 6.1 / Boot 3.2+; a `TaskDecorator` bean is applied to the
  auto-configured executor, call `setTaskDecorator(...)` on your own) so MDC and the trace context survive the
  thread hop. There is no Spring `MdcTaskDecorator`; don't hand-roll one.
- For `Mono`/`Flux`, enable automatic context propagation
  (`spring.reactor.context-propagation: auto`, Boot 3.2+) so MDC follows the
  Reactor Context — the hand-written `MdcContextLifter` hook is no longer needed.

**Log-level governance.**
- `ERROR` — unexpected, requires alert.
- `WARN`  — recoverable, may indicate a downstream issue.
- `INFO`  — once per request at most; one line per business decision.
- `DEBUG` — disabled in prod by default; enabled per package via env var.
- **Never** log secrets, full URLs with credentials, JWTs, or PII without
  redaction.

## 3. Distributed traces — OpenTelemetry

```xml
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-tracing-bridge-otel</artifactId>
</dependency>
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>
```

```yaml
management:
  tracing:
    sampling.probability: 0.05  # base / prod: 5 %; raise per incident
  otlp:
    tracing:
      endpoint: http://otel-collector:4318/v1/traces   # OTLP over HTTP (Boot's default transport; gRPC needs management.otlp.tracing.transport=grpc)
  opentelemetry:
    resource-attributes:
      service.version: {{version}}
spring:
  application.name: {{artifactId}}                      # becomes the OpenTelemetry service.name
```

`application-local.yaml` (and dev / staging profiles) raise sampling to 100 %:

```yaml
management.tracing.sampling.probability: 1.0
```

These property names are for Spring Boot 3.5. Boot 4 moved the OpenTelemetry/OTLP properties and starters — check
its migration guide before upgrading.

Conventions:
- W3C TraceContext headers (`traceparent`/`tracestate`) propagate
  automatically across `RestClient`/`WebClient` calls. **Never** invent
  your own correlation header.
- Custom spans only at meaningful boundaries (a use-case operation, an
  external call, an async hand-off). Span name = `<verb>_<noun>`
  (`export_invoice`), not the class+method name.
- Add span attributes for the business identifiers (`invoice.id`,
  `file.id`) but **not** for PII.

## 4. SLI / SLO conventions

Each service publishes (in `docs/SLO.md`) at least:

| SLI | Target | Window |
| --- | --- | --- |
| Availability — `2xx / total` on public endpoints | 99.9 % | 28 days rolling |
| Latency — share of primary-use-case requests faster than 500 ms (`le="0.5"` SLO bucket of the `request-metrics` Timer ÷ count) | ≥ 95 % | 28 days rolling |
| Freshness (if applicable) | service-specific | service-specific |

The latency SLI is computed from the Timer's SLO buckets (`MetricsTimerHelper`), not from a p95: percentile
histograms are off by default to bound cardinality. If a true p95 is needed, enable
`management.metrics.distribution.percentiles-histogram.<metric>: true` for that metric only.

Error budget = `1 − SLO`. Alerts fire on **burn rate** (multi-window),
never on raw error counts.

## 5. Dashboards as code

- Ship dashboards as JSON under `observability/dashboards/` and provision
  them via Grafana operator / `kube-prometheus-stack`.
- One **service overview** dashboard per service + one **per business
  use-case** dashboard.
- Alerts live in `observability/alerts/*.yaml` as Prometheus rules.

## 6. Business Metrics (Micrometer)

While `timer` and `counter` cover 90% of use cases, use **Gauges** for instantaneous values (e.g., current queue size, number of active connections).

```java
@Component
public class QueueMonitor {
    private final AtomicInteger queueSize = new AtomicInteger(0);

    public QueueMonitor(MeterRegistry registry) {
        Gauge.builder("foo.exports.queued", queueSize, AtomicInteger::get)   // <service>.<domain>.<state>
            .description("Current number of exports waiting in the queue")
            .register(registry);
    }

    public void setSize(int size) { this.queueSize.set(size); }
}
```

Rules:
- **Never** create a Gauge that performs a heavy DB query — it is polled frequently by Prometheus.
- Use an `AtomicInteger` or `AtomicLong` as the state holder.
- Register the Gauge only once (usually in the constructor).


## 7. Do / Don't

✅ MDC is the only place correlation lives; never pass `traceId` as a method
parameter.
✅ Cardinality discipline: every new tag passes a `< 100 unique values`
sniff test before being added.
✅ One JSON-per-line log encoder; one OTel exporter per service.
❌ Never log full request/response bodies in `INFO`. Use `DEBUG` and
redact PII.
❌ Never invent a correlation header — W3C TraceContext is the standard.
❌ Never sample at 100 % in production — the bill and the storage will hurt.

The logic for tag extraction belongs in a `monitor/parser/` class (`request-metrics`), keeping the `Operation` logic clean.

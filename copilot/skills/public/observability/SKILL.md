---
name: observability
description: Wire the three observability pillars — metrics (Micrometer + Prometheus), structured JSON logs with MDC correlation IDs, and distributed traces (OpenTelemetry) — into a Spring Boot service. Defines SLI/SLO conventions and a Filter + Recorder pattern for per-request domain metrics. Use whenever a new service is created or when observability gaps prevent debugging in production.
tier: must
applies_to: [rest, event, scheduler, monolith]
depends_on: [code-structure, pluggable-architecture]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Observability Skill (public)

A microservice is only as good as the signals it emits. This skill makes the
three pillars uniform across every service.

## 1. Metrics — Micrometer + Prometheus

Already wired by `spring-boot-starter-actuator` + `micrometer-registry-prometheus`.
Conventions:

- **Naming.** `<service>.<domain>.<verb>` — e.g. `foo.documents.converted`.
  All lowercase + dots; never CamelCase.
- **Tags.** Keep cardinality bounded. `status` (`success`/`error`),
  `target_format`, `caller_type`. **Never** a free-form id, URL, or message.
- **Types.** `Counter` for events; `Timer` for latencies (records count +
  histogram); `Gauge` for current values (queue depth, pool size).
- **Use the Filter + Recorder Registry pattern** from `code-structure` §3 so
  business metrics are added by *new classes*, never by editing the filter.

```java
meterRegistry.timer("foo.documents.converted",
        "source_format", src, "target_format", tgt, "status", "success")
    .record(elapsed);
```

## 2. Structured JSON logs + MDC

Use **Logback with `logstash-logback-encoder`** or `logback-spring.xml` with
the `LogstashEncoder` so logs are one JSON object per line — directly
indexable by Elastic / Loki / Datadog without a parser.

```xml
<dependency>
    <groupId>net.logstash.logback</groupId>
    <artifactId>logstash-logback-encoder</artifactId>
    <version>7.4</version>
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
- Put `traceId` / `spanId` / `callerId` into MDC at the request boundary
  (`OncePerRequestFilter`), clear them in `finally`.
- For `@Async` / `CompletableFuture`, decorate the executor with
  `MdcTaskDecorator` so MDC survives the thread hop.
- For `Mono`/`Flux`, use Reactor Context + the `MdcContextLifter` pattern.

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
    sampling.probability: 1.0   # 100% in dev / staging; 0.05 in prod, raise per incident
otel:
  exporter.otlp.endpoint: http://otel-collector:4317
  resource.attributes: service.name={{artifactId}},service.version={{version}}
```

Conventions:
- W3C TraceContext headers (`traceparent`/`tracestate`) propagate
  automatically across `RestClient`/`WebClient` calls. **Never** invent
  your own correlation header.
- Custom spans only at meaningful boundaries (a use-case operation, an
  external call, an async hand-off). Span name = `<verb>_<noun>`
  (`convert_document`), not the class+method name.
- Add span attributes for the business identifiers (`document.id`,
  `file.id`) but **not** for PII.

## 4. SLI / SLO conventions

Each service publishes (in `docs/SLO.md`) at least:

| SLI | Target | Window |
| --- | --- | --- |
| Availability — `2xx / total` on public endpoints | 99.9 % | 28 days rolling |
| Latency — p95 of `Timer{success}` on the primary use case | < 500 ms | 28 days rolling |
| Freshness (if applicable) | service-specific | service-specific |

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
        Gauge.builder("business.queue.size", queueSize, AtomicInteger::get)
            .description("Current number of items in the business queue")
            .register(registry);
    }

    public void setSize(int size) { this.queueSize.set(size); }
}
```

Rules:
- **Never** create a Gauge that performs a heavy DB query — it is polled frequently by Prometheus.
- Use an `AtomicInteger` or `AtomicLong` as the state holder.
- Register the Gauge only once (usually in the constructor).


## 8. Do / Don't

✅ MDC is the only place correlation lives; never pass `traceId` as a method
parameter.
✅ Cardinality discipline: every new tag passes a `< 100 unique values`
sniff test before being added.
✅ One JSON-per-line log encoder; one OTel exporter per service.
❌ Never log full request/response bodies in `INFO`. Use `DEBUG` and
redact PII.
❌ Never invent a correlation header — W3C TraceContext is the standard.
❌ Never sample at 100 % in production — the bill and the storage will hurt.

The logic for tag extraction belongs in a `monitor/parsers/` class, keeping the `Operation` logic clean.

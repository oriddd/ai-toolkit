---
name: request-metrics
description: >
  Java / Spring Boot per-endpoint Micrometer timers via Filter + Recorder + Parser — one OncePerRequestFilter, one
  MetricsRecorder per use case, pluggable tag parsers. Use when adding a timed, domain-meaningful endpoint metric.
  General logs, traces and metrics wiring is `observability`.
tier: must
applies_to: [rest, monolith]
depends_on: [code-structure, observability, spring-boot-conventions, strategy-registry-pattern]
ships_templates: false
hitl: false
version: 1.1
last_reviewed: 2026-07-12
---

# Request Metrics Skill
> **Pattern Foundation:** This skill is a concrete application of the strategy-registry-pattern skill. 
> Read that skill first to understand the foundational pattern, then return here for the metrics-specific implementation.

Domain metrics in a Spring Boot service live in a dedicated `monitor/` package
that follows the **Filter → Recorder → Parser** pattern. A single filter
measures every request; a registry routes to the right recorder; parsers extract
structured tags. Adding a metric for a new endpoint requires exactly
**one new `MetricsRecorder` class, one `MonitoringConfig` entry and one `MonitoringConstants` constant** (plus a
parser only if it needs a new domain tag) — the filter, registry and existing parsers never change. This is the open/closed principle (OCP) applied to observability.

> This skill applies the **Filter-based variation** of the strategy-registry-pattern.
> `observability` covers the three-pillar platform setup (Micrometer, structured logs, OpenTelemetry). 
> This skill covers domain-level per-request metrics on top of that foundation.

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
│   └── <Domain>Parser.java         # one per additional domain tag (format, orderType, …)
└── recorder/
    ├── MetricsRecorder.java         # interface: recordMetrics + getSupportedMetricName + canHandle
    ├── MetricsRecorderRegistry.java # injects List<MetricsRecorder>, routes by metric name
    └── <UseCase>MetricsRecorder.java  # one per business use case that needs a metric
```

## Reference map — load only the part you are working on

Sections below keep their numbers but live in `references/` so this file stays small. Read only the file you need; do not load them all.

| Sections | Topic | Load when | File |
| --- | --- | --- | --- |
| §2–§5 | `MonitoringConfig`, `MonitoringConstants`, `MetricsFilter`, `MetricNameResolver` | wiring the filter and URI-to-metric-name map | [`config-filter-and-resolver.md`](./references/config-filter-and-resolver.md) |
| §6–§8 | tag parsers, `MetricsTagsHelper`, `MetricsTimerHelper` | extracting tags or building the Timer with SLO buckets | [`parsers-and-helpers.md`](./references/parsers-and-helpers.md) |
| §9–§11 | `MetricsRecorder`, `MetricsRecorderRegistry`, adding a use-case recorder | adding a new metric (the only change needed) | [`recorders-and-registry.md`](./references/recorders-and-registry.md) |
| §12 | tests for the metrics stack | testing filter, parsers or recorders | [`testing.md`](./references/testing.md) |

## Do / Don't

✅ Add a new metric by adding **one** `MetricsRecorder` + one entry in
   `MonitoringConfig` + one constant in `MonitoringConstants` — never touch the filter or registry.
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
❌ Never emit a blank tag value — Prometheus treats it as "label absent", merging unrelated requests into one ambiguous series.
❌ Never add business logic to `MetricsFilter` — it only measures, routes, and
   delegates.

## Cross-references

- `observability` — three-pillar platform setup
  (Micrometer registry, structured logs, OpenTelemetry); this skill adds
  domain-level per-request metrics on top.
- `code-structure` §3 — Pattern B overview that
  this skill fully expands.
- `unit-tests` — parser and recorder unit-test shapes.
- `spring-boot-conventions` — typed
  `@ConfigurationProperties` if `MonitoringConfig` grows beyond a short ordered list.


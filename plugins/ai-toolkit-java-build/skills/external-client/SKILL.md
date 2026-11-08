---
name: external-client
description: >
  Java / Spring Boot: SDK-style package for a downstream service (HTTP, gRPC, broker, file store) — Service facade,
  CoreService, thin Client, request builders, response parsers/verifiers, Config. Use when a new downstream dependency
  or external API is introduced.
tier: must
applies_to: [rest, event, scheduler, monolith]
depends_on: [code-structure, observability, pluggable-architecture]
ships_templates: true
hitl: true
version: 2.1
last_reviewed: 2026-07-13
---

# External Client Skill

Every external dependency is wrapped in its own **self-contained sub-package**
under `client/`. The package is a mini-SDK: consumers depend on **one**
domain-friendly `*Service` facade and never see `WebClient`, `Mono`, SDK types,
or remote DTOs. This is the **lego-brick** convention.

## 0. CRITICAL: Pattern Selection (Human-in-the-Loop Required)

**STOP: Before applying this skill, ASK the developer:**

1. **API Complexity**: Is this a simple REST CRUD API or complex SDK integration?
2. **Current Scale**: How many API endpoints/methods do you need NOW?
3. **Future Growth**: Do you expect this to grow to 10+ endpoints in next 6 months?
4. **Query Complexity**: Does this API require complex query building (filters, DSL)?
5. **Response Complexity**: Is response parsing simple (1:1 JSON mapping) or complex (nested transformations)?

### Decision Tree

Based on answers, use this pattern:

#### Pattern 1: Simple RestClient Wrapper (1-4 simple CRUD endpoints)
**Use when:**
- ✅ Simple REST CRUD (GET, POST, PUT, DELETE)
- ✅ 1-4 endpoints currently needed
- ✅ No complex query building
- ✅ Simple JSON → POJO mapping
- ✅ No shared request/response logic

**Structure (3 files, ~300 LOC):**
```
client/<dep>/
├── <Dep>Client.java              # All-in-one: RestClient + methods
├── <Dep>ClientConfig.java        # RestClient bean
└── <Dep>Properties.java          # @ConfigurationProperties
```

**Example**: Simple CRUD microservice, basic lookup service, health check proxy

#### Pattern 2: Lite Client (5-9 endpoints, some complexity)
**Use when:**
- ✅ 5-9 endpoints
- ✅ Some shared query building (pagination, filtering)
- ✅ Some response parsing complexity
- ✅ Growing but still manageable

**Structure (5-6 files, ~500 LOC):**
```
client/<dep>/
├── <Dep>Client.java              # RestClient wrapper
├── <Dep>ClientConfig.java
├── <Dep>Properties.java
├── <Dep>RequestBuilder.java      # Shared query/filter building
└── <Dep>ResponseParser.java      # Shared response extraction
```

**Example**: Paginated list APIs, filtered search with 5-10 filters

#### Pattern 3: Full 5-Layer SDK Pattern (10+ endpoints, high complexity)
**Use when:**
- ✅ 10+ endpoints OR
- ✅ Complex query DSL (Elasticsearch-style) OR
- ✅ Multi-step protocols (Kafka producer patterns) OR
- ✅ Heavy DTO transformation (SDK types → domain models) OR
- ✅ Shared filter builders used across many operations

**Structure (7-9 files, ~800 LOC):**
```
client/<dep>/
├── <Dep>Service.java             # Facade
├── constant/<Dep>Constants.java
├── core/
│   ├── <Dep>ClientConfig.java
│   ├── <Dep>Client.java
│   └── <Dep>CoreService.java
└── handler/
    ├── request/<Dep>RequestBuilder.java
    └── response/
        ├── <Dep>ResponseParser.java
        └── <Dep>ResponseVerifier.java
```

**Example**: Elasticsearch integration, Kafka with custom protocols, AWS SDK wrappers

### When Uncertain: Start Simple, Refactor When Needed

**Default Rule**: If unsure, start with Pattern 1 (Simple Wrapper). Refactor to Pattern 2 or 3 when:
- You add 5th similar method and see duplication
- Request building becomes complex (>10 lines per method)
- Response parsing diverges significantly per operation

**It's easier to add layers than remove them.**

## 1. Canonical package structure

```
client/<dependency-name>/
├── <Dep>Service.java                         # public domain facade — the only class callers import
├── constant/
│   └── <Dep>Constants.java                   # field names, query IDs, sentinel values
├── core/
│   ├── <Dep>ClientConfig.java                # @Configuration — transport bean
│   ├── <Dep>Client.java                      # thin HTTP/gRPC transport, one method per remote op
│   └── <Dep>CoreService.java                 # orchestrator: build → call → parse/verify
└── handler/
    ├── request/
    │   ├── <Dep>RequestBuilder.java           # assembles SDK request DTOs from domain primitives
    │   └── <Dep>FilterMapBuilder.java         # fluent filter-map builder (keeps callers clean)
    └── response/
        ├── <Dep>ResponseParser.java           # extracts domain values from response DTOs
        └── <Dep>ResponseVerifier.java         # checks response conditions (hasHits, isSuccess…)
```

Layering — callers only touch the top row; every layer below is invisible:

```
operation / service
      │
      ▼
  <Dep>Service                  ← public API, domain method names
      │
      ▼
  <Dep>CoreService              ← orchestrates: FilterMapBuilder → RequestBuilder → Client → Parser/Verifier
      │                ├──► <Dep>RequestBuilder  (request DTO assembly)
      │                ├──► <Dep>FilterMapBuilder (fluent filter composition)
      ├──► <Dep>Client           ← thin transport, one method per remote endpoint
      ├──► <Dep>ResponseParser   ← extracts values from response DTOs
      └──► <Dep>ResponseVerifier ← boolean checks on response state
```

## 2–11b. Reference map — load only the file for the layer you are writing

Sections §2–§11b keep their numbers but live in `references/` so this file stays small. Read the one you need;
do not load them all.

| Section | Topic | Load when | File |
| --- | --- | --- | --- |
| §2 | `<Dep>Service` facade | writing the public class callers import | [`layers.md`](./references/layers.md) |
| §3 | `<Dep>FilterMapBuilder` | composing filters fluently | [`layers.md`](./references/layers.md) |
| §4 | `<Dep>CoreService` | wiring build → call → parse | [`layers.md`](./references/layers.md) |
| §5 | `<Dep>RequestBuilder` | assembling request DTOs | [`layers.md`](./references/layers.md) |
| §6 | `<Dep>Client` + `<Dep>ClientConfig` | writing the transport and its bean | [`transport-and-responses.md`](./references/transport-and-responses.md) |
| §7 | `<Dep>ResponseParser` + `<Dep>ResponseVerifier` | extracting values / checking responses | [`transport-and-responses.md`](./references/transport-and-responses.md) |
| §8 | `<Dep>Constants` | field names, query IDs | [`transport-and-responses.md`](./references/transport-and-responses.md) |
| §9 | Spring properties | wiring base URL, endpoints, timeouts | [`config-and-resilience.md`](./references/config-and-resilience.md) |
| §10 | Resilience4j | retry / circuit breaker | [`config-and-resilience.md`](./references/config-and-resilience.md) |
| §11 | Tests | writing tests for the package | [`tests-and-growth.md`](./references/tests-and-growth.md) |
| §11b | Growth path | `client/<dep>/` is outgrowing pure transport | [`tests-and-growth.md`](./references/tests-and-growth.md) |

## Do / Don't

✅ Callers import only `*Service` — never `*Client`, `*CoreService`, or any
   remote DTO.
✅ Use `exchangeToMono` + a private `handleResponse(response, type)` in
   `*Client` to read error body before throwing a domain exception.
✅ Keep `*FilterMapBuilder` as a non-Spring plain object — instantiated with
   `new` at the call site for fluent, readable filter composition.
✅ Split `*ResponseParser` (extract values) from `*ResponseVerifier`
   (boolean checks) — they have different change rates and test shapes.
✅ All remote field names and query IDs live in `*Constants` — never inline.
❌ Never let `WebClientResponseException`, `Mono`, `Flux`, or remote DTO
   types escape the `client/<dep>/` package boundary.
❌ Never put retry, circuit-breaker, or metrics logic inside `*Client` itself —
   use Resilience4j annotations or the Decorator pattern on a client interface.
❌ Never return a "default" / silent empty value from a fallback — throw a
   domain exception so the `@RestControllerAdvice` maps it to `503`.
❌ Never share one `WebClient` bean across two external dependencies.
❌ Never keep repository/analyzer/scheduler code under `client/<dep>/`
   once the integration has grown past pure transport — see §11b Growth path.
❌ Never read the same dependency property (endpoint, namespace, topic)
   via `@Value` in more than one class; inject the shared
   `@ConfigurationProperties` bean instead.

## Cross-references

- `code-structure` — layering rules and package
  conventions the `client/` sub-package follows.
- `exception-handling` — domain exception
  hierarchy; `*Client` throws subclasses.
- `resilience-patterns` — bulkheads,
  timeouts, circuit breakers beyond simple retries.
- `health-indicator` — add a readiness
  probe for the new dependency.
- `observability` — correlation IDs propagated
  through client calls; per-call metrics via `request-metrics`.
- `pluggable-architecture` — when the
  same capability (e.g. search) must support multiple backends, expose
  `*Service` as a port interface and put each backend under `adapter/`.

## 12. Templates

- [`CacheClientConfig.java.tmpl`](./templates/CacheClientConfig.java.tmpl) — Configuration for an external cache.
- [`CacheClient.java.tmpl`](./templates/CacheClient.java.tmpl) — Thin transport implementation.
- [`CacheEntryResponse.java.tmpl`](./templates/CacheEntryResponse.java.tmpl) — Remote DTO.
- [`CacheEntryAdapter.java.tmpl`](./templates/CacheEntryAdapter.java.tmpl) — Translation to domain model.

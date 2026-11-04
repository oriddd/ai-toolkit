---
name: strategy-registry-pattern
description: >
  Java / Spring Boot Strategy + Registry + Handler for runtime-selected behaviour — add a strategy class, never edit
  the dispatcher (Open/Closed). Use when several implementations are chosen at runtime by URI, caller, parameter or
  version. Not for plain validation.
tier: foundational
applies_to: [rest, event, monolith]
depends_on: [code-structure, spring-boot-conventions]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-07-12
---

# Strategy + Registry + Handler/Filter Pattern (Foundational)

This is the **foundational pattern** for implementing pluggable, extensible behavior in Spring Boot microservices. It achieves the **Open/Closed Principle** by allowing new behavior to be added through new strategy classes without modifying existing dispatcher code.

## Pattern Overview

The pattern consists of these components:

```
<domain-package>/
├── <Domain>Handler.java              # Dispatcher - orchestrates the flow
├── <Domain>Registry.java             # Registry - routes to the right strategy
├── <Domain>Strategy.java             # Interface - defines the contract
├── <Context>Resolver.java            # Resolver - determines which strategy to use
├── <Helper>Helper.java               # Optional - shared logic across strategies
├── parser/                           # Parsers - extract data from context
│   ├── <Concept>Parser.java
│   └── ...
└── strategy/                         # Strategies - concrete implementations
    ├── <UseCase>Strategy.java
    └── ...
```

**OR** for request-scoped concerns (like metrics, logging, security):

```
<domain-package>/
├── <Domain>Filter.java               # Filter - intercepts every request (OncePerRequestFilter)
├── <Domain>Registry.java             # Registry - routes to the right strategy
├── <Domain>Strategy.java             # Interface - defines the contract
├── <Context>Resolver.java            # Resolver - determines which strategy to use
├── <Helper>Helper.java               # Optional - shared logic
├── parser/                           # Parsers - extract data from request/response
│   ├── <Concept>Parser.java
│   └── ...
└── strategy/                         # Strategies - concrete implementations
    ├── <UseCase>Strategy.java
    └── ...
```

## Reference map — load only the part you are working on

Sections below keep their numbers but live in `references/` so this file stays small. Read only the file you need; do not load them all.

| Sections | Topic | Load when | File |
| --- | --- | --- | --- |
| Component Responsibilities | strategy interface, strategies, registry, handler/filter — with code | implementing the pattern's classes | [`components.md`](./references/components.md) |

## When to Use This Pattern

✅ **Use when:**
- Multiple implementations of the same concern (metrics, permissions, layouts, formats)
- Runtime selection based on context (URI, caller type, query param, API version)
- Adding new behavior should NOT require modifying existing code (Open/Closed Principle)
- All strategies handle the same bounded concern

**Examples:**
- ✅ Monitoring — record different metrics per endpoint
- ✅ Permissions — check authorization for different caller types (USER, SERVICE_ACCOUNT, EXTERNAL)
- ✅ Response layouts — return summary/detailed/full field sets
- ✅ API versioning — map entities to v1/v2/v3 DTOs
- ✅ Multi-format responses — JSON, XML, CSV exporters
- ✅ Multi-tenant behavior variations

❌ **Don't use when:**
- Only one implementation exists (no variation needed)
- Simple 2-3 case if/else is sufficient (pattern may be overkill)
- Compile-time selection is enough (use Spring `@Conditional` beans)
- Behavior is tightly coupled across strategies (shared state complicates the pattern)

## Adding a New Strategy

**Checklist:**
1. ✅ Create a new `<UseCase>Strategy implements Strategy` in `strategy/`
2. ✅ Make it a `@Component`
3. ✅ Implement `getSupportedXxx()` or `supportedContexts()`
4. ✅ Implement the core behavior method
5. ✅ If new tag/data extraction is needed, add a new `<Concept>Parser` in `parser/`
6. ✅ If a new discriminator value is needed, update the Resolver or Config
7. ✅ Write unit tests for the strategy and any new parsers

**Zero changes needed:**
- ❌ Handler/Filter
- ❌ Registry
- ❌ Strategy interface
- ❌ Existing strategies

## Testing

### Test the Handler/Filter
- ✅ Happy path — strategy found and executed
- ✅ No strategy found — logs warning / throws exception
- ✅ Exception in strategy — propagates with original message
- ✅ (For Filters) Exception in filter chain — strategy still executed in `finally`

### Test the Resolver
- ✅ Valid input → returns expected discriminator
- ✅ Invalid input → returns `null`
- ✅ Edge cases (null request, missing headers, malformed URIs)

### Test the Registry
- ✅ Matching strategy → returns the strategy
- ✅ No matching strategy → returns `null`
- ✅ Multiple strategies, correct one selected

### Test Each Strategy
- ✅ `canHandle` returns `true` for its discriminator
- ✅ `canHandle` returns `false` for other discriminators
- ✅ Core behavior method executes correctly
- ✅ All exception branches covered

### Test Each Parser
- ✅ Valid input → returns expected value
- ✅ Invalid input → returns sentinel (UNKNOWN, DEFAULT)
- ✅ Exception → returns sentinel, logs error

## Do / Don't

✅ **Do:**
- Add new behavior by adding a new `@Component` strategy — never modify Handler/Registry
- Return non-blank sentinel values from Parsers — never `null` or `""`
- Keep the Handler/Filter generic — no strategy-specific logic
- Use `List<Strategy>` injection in Registry — Spring auto-discovers
- Delegate tag/data extraction to Parsers — keep strategies DRY

❌ **Don't:**
- Add if/else or switch on strategy type in Handler/Registry
- Let strategies reference other strategies directly
- Inline data extraction logic in strategies — use Parsers
- Return `null` from Parsers — return sentinel values
- Skip unit tests for new strategies/parsers

## Related Skills

This pattern is applied in:
- **request-metrics** — Filter + Recorder + Parser for domain metrics
- **permissions** — Handler + Strategy for authorization
- **response-layout** — Handler + Strategy for layout query parameters
- **response-mapper** — Handler + Strategy for entity→DTO mapping

## Variations

### Handler-based (synchronous operations)
Use when the concern is invoked explicitly in business logic:
- Permissions checking (`permissionsHandler.handle(resourceId)`)
- Data mapping (`responseMapper.map(entity, layout)`)

### Filter-based (request-scoped cross-cutting concerns)
Use when the concern applies to every request:
- Metrics recording (intercept all requests, measure time)
- Request logging / MDC setup
- Request/response transformation

### Config-driven Resolver
When the discriminator is determined by a config map (URI patterns → metric names):
```java
@Getter
@Configuration
public class MonitoringConfig {
    private final Map<Pattern, String> patternToMetricNameMap = Map.of(
        Pattern.compile("/api/v1/invoices/[^/]+/export"), "service.invoices.export",
        Pattern.compile("/api/v1/reports"), "service.reports.create"
    );
}
```

### Enum-driven Resolver
When the discriminator is a fixed set of values (caller contexts, layout types):
```java
public enum CallerContext { USER, SERVICE_ACCOUNT, EXTERNAL_SYSTEM, BASIC_AUTH }
```

## Implementation Checklist

When implementing this pattern:
- [ ] Identify the **bounded concern** (what are all strategies doing?)
- [ ] Define the **discriminator** (what determines which strategy to use?)
- [ ] Define the **Strategy interface** (what contract do all strategies share?)
- [ ] Create the **Resolver** (how to extract the discriminator from context?)
- [ ] Create the **Registry** (routes discriminator → strategy)
- [ ] Create the **Handler or Filter** (orchestrates resolver → registry → strategy)
- [ ] Create **Parsers** for reusable data extraction (optional but recommended)
- [ ] Create **Helpers** for shared logic (optional)
- [ ] Implement **concrete strategies** as `@Component` beans
- [ ] Write **unit tests** for each component
- [ ] Document when to add a new strategy (should be additive only)

---

**Version:** 1.0  
**Last Reviewed:** 2026-07-12

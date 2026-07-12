---
name: strategy-registry-pattern
description: Foundational architectural pattern for implementing pluggable, extensible behavior in Spring Boot microservices. Uses Strategy + Registry + Handler/Filter to achieve Open/Closed Principle — add new behavior by adding new strategy classes, never by modifying existing dispatcher code. Apply when you have multiple implementations of the same concern that are selected at runtime based on context (URI pattern, caller type, query parameter, API version, etc.).
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

## Component Responsibilities

### 1. **Handler (or Filter)** — The Dispatcher

**Responsibility:** Orchestrate the flow. Resolve context, find the right strategy, delegate.

**Rules:**
- ✅ Handles the request lifecycle (for Filters: measure time, ensure finally block)
- ✅ Delegates to Resolver → Registry → Strategy
- ✅ **Never** contains strategy-specific logic or if/else on strategy type
- ✅ Logs warnings when no strategy is found
- ✅ Is a `@Component` or extends `OncePerRequestFilter`

**Example (Handler):**
```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class PermissionsHandler {
    private final CallerContextResolver callerContextResolver;
    private final PermissionsRegistry permissionsRegistry;

    public void handle(final String resourceId) {
        final CallerContext ctx = callerContextResolver.resolve();
        final PermissionsStrategy strategy = permissionsRegistry.getStrategy(ctx);
        if (strategy == null) {
            throw new ForbiddenException("No strategy found for context: " + ctx);
        }
        strategy.verifyPermissions(resourceId);
    }
}
```

**Example (Filter):**
```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class MetricsFilter extends OncePerRequestFilter {
    private final MetricNameResolver metricNameResolver;
    private final MetricsRecorderRegistry metricsRecorderRegistry;

    @Override
    protected void doFilterInternal(HttpServletRequest request, 
                                    HttpServletResponse response, 
                                    FilterChain filterChain) 
            throws ServletException, IOException {
        final long startMs = System.currentTimeMillis();
        try {
            filterChain.doFilter(request, response);
        } finally {
            final String metricName = metricNameResolver.resolve(request);
            final MetricsRecorder recorder = metricsRecorderRegistry.getRecorder(metricName);
            if (recorder != null) {
                recorder.recordMetrics(System.currentTimeMillis() - startMs, request, response);
            }
        }
    }
}
```

### 2. **Resolver** — Context Determination

**Responsibility:** Determine which strategy to use based on input context.

**Rules:**
- ✅ Reads request/context and returns a discriminator (String, Enum, etc.)
- ✅ Returns `null` when no match (Handler/Filter logs warning)
- ✅ **Never** contains business logic
- ✅ Is a `@Component`

**Examples:**
- `MetricNameResolver` — URI pattern → metric name (String)
- `CallerContextResolver` — Authentication → CallerContext (Enum)
- `LayoutResolver` — Query param `?layout=X` → LayoutType (Enum)
- `ApiVersionResolver` — Accept header / URI → ApiVersion (Enum)

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class MetricNameResolver {
    private final MonitoringConfig monitoringConfig;

    public String resolve(final HttpServletRequest request) {
        if (request == null || request.getRequestURI() == null) {
            return null;
        }
        final String uri = request.getRequestURI();
        return monitoringConfig.getPatternToMetricNameMap().entrySet().stream()
                .filter(entry -> entry.getKey().matcher(uri).matches())
                .map(Map.Entry::getValue)
                .findFirst()
                .orElse(null);
    }
}
```

### 3. **Registry** — Strategy Routing

**Responsibility:** Hold all strategies and route to the right one based on the discriminator.

**Rules:**
- ✅ Injects `List<Strategy>` via constructor — Spring auto-discovers all implementations
- ✅ Filters strategies by calling `canHandle(discriminator)` on each
- ✅ Returns `null` when no strategy matches
- ✅ **Never** contains if/else or switch on strategy type
- ✅ Is a `@Component`

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class MetricsRecorderRegistry {
    private final List<MetricsRecorder> metricsRecorders;

    public MetricsRecorder getRecorder(final String metricName) {
        return metricsRecorders.stream()
                .filter(r -> r.canHandle(metricName))
                .findFirst()
                .orElse(null);
    }
}
```

### 4. **Strategy Interface** — The Contract

**Responsibility:** Define the contract that all strategies must implement.

**Rules:**
- ✅ Defines the core behavior method (e.g., `recordMetrics`, `verifyPermissions`, `map`)
- ✅ Defines `canHandle(discriminator)` — used by Registry for routing
- ✅ Provides a default `canHandle` implementation when possible
- ✅ Is an `interface` (not an abstract class unless shared state is needed)

```java
public interface MetricsRecorder {
    void recordMetrics(long durationMs, HttpServletRequest request, HttpServletResponse response);
    String getSupportedMetricName();

    default boolean canHandle(final String metricName) {
        return StringUtils.isNotBlank(getSupportedMetricName())
                && StringUtils.isNotBlank(metricName)
                && getSupportedMetricName().equals(metricName);
    }
}
```

### 5. **Concrete Strategies** — Implementations

**Responsibility:** Implement the behavior for a specific use case.

**Rules:**
- ✅ Each strategy is a `@Component`
- ✅ Implements the Strategy interface
- ✅ Returns its discriminator value via `getSupportedXxx()` or `supportedContexts()`
- ✅ **Never** references other strategies directly
- ✅ Delegates tag/data extraction to Parsers, not inline

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
@Slf4j
public class ConvertEntityMetricsRecorder implements MetricsRecorder {
    private final MetricsTimerHelper metricsTimerHelper;
    private final TargetFormatParser targetFormatParser;

    @Override
    public String getSupportedMetricName() {
        return MonitoringConstants.METRIC_CONVERT_ENTITY;
    }

    @Override
    public void recordMetrics(final long durationMs,
                              final HttpServletRequest request,
                              final HttpServletResponse response) {
        final Tag targetFormatTag = Tag.of("targetFormat",
                targetFormatParser.parseTargetFormat(request));
        final Timer timer = metricsTimerHelper.buildTimerWithExtraTags(
                getSupportedMetricName(), request, response, targetFormatTag);
        timer.record(durationMs, TimeUnit.MILLISECONDS);
    }
}
```

### 6. **Parsers** — Data Extraction

**Responsibility:** Extract specific data from request/response/context.

**Rules:**
- ✅ One parser per extractable concept (HTTP method, client ID, target format, layout type)
- ✅ Each parser is a `@Component`
- ✅ Returns a non-blank sentinel value (`UNKNOWN`, `DEFAULT`) on failure — **never** `null` or `""`
- ✅ Swallows exceptions with `log.error` and returns sentinel
- ✅ Method naming: `parse<Concept>(request|response|...)`

```java
@Component
@Slf4j
public class ClientIdParser {
    private static final String AZP = "azp";

    public String parseClientId() {
        try {
            final Authentication auth = SecurityContextHolder.getContext().getAuthentication();
            if (auth instanceof JwtToken jwt
                    && jwt.getTokenAttributes() != null
                    && jwt.getTokenAttributes().get(AZP) != null) {
                return String.valueOf(jwt.getTokenAttributes().get(AZP));
            }
            if (auth instanceof BasicAuthenticationToken) {
                return MonitoringConstants.BASIC;
            }
        } catch (final Exception e) {
            log.error("Failed to extract clientId", e);
        }
        return MonitoringConstants.UNKNOWN;
    }
}
```

### 7. **Helpers** — Shared Logic (Optional)

**Responsibility:** Provide shared utilities or tag-building logic used by multiple strategies.

**Rules:**
- ✅ Only create when multiple strategies need the same logic
- ✅ Is a `@Component`
- ✅ Composes Parsers to build common tag sets or structures

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
            Tag.of("requestMethod", requestMethodParser.parseRequestMethod(request)),
            Tag.of("responseStatus", responseStatusParser.parseResponseStatus(response)),
            Tag.of("clientId", clientIdParser.parseClientId())
        );
    }
}
```

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
        Pattern.compile("/api/v1/entities/[^/]+/convert"), "service.entities.convert",
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

# Pattern Selection Guide: Scale-Based Decision Making

**Purpose**: Prevent over-engineering by choosing patterns appropriate to actual scale and complexity.

**Key Principle**: **Start simple, add complexity when justified by actual needs.**

> The examples are Java / Spring Boot; the principle applies unchanged to every language
> (Python, React Native, …): choose the smallest pattern that fits the actual scale.

---

## The Over-Engineering Trap

### What Happened
A project needed a simple REST client for CRUD operations (4 endpoints). The full 5-layer external-client pattern was applied:
- ✅ Facade (guard clauses)
- ✅ CoreService (orchestration)
- ✅ Client (HTTP transport)
- ✅ RequestBuilder (URI building)
- ✅ ResponseParser + ResponseVerifier

**Result**: 9 files, ~500 LOC for something that needed 3 files, ~250 LOC.

### Root Cause
**Literal pattern application without evaluating necessity.**

The documentation said "use external-client pattern for external services" without explaining **when to use which variant**.

---

## Scale-Based Decision Framework

### External Client Patterns

| Scale | Pattern | Files | LOC | Use When |
|-------|---------|-------|-----|----------|
| **Small** (1-4 endpoints) | Simple Wrapper | 3 | ~250 | Simple CRUD, basic lookups, health checks |
| **Medium** (5-9 endpoints) | Lite Client | 5 | ~500 | Some query building, pagination, filtering |
| **Large** (10+ endpoints) | Full 5-Layer | 7-9 | ~800 | Complex DSL (Elasticsearch), multi-step protocols, heavy transformations |

### Operation Layer Decision

The controller holds no logic and delegates to exactly **one** collaborator (guild rule #3,
`code-structure`): a `*Service` when the use case is a single service call, an `*Operation`
as soon as it orchestrates several. Scale decides how much structure lives behind it.

| Complexity | Pattern | LOC Threshold | Use When |
|------------|---------|---------------|----------|
| **Trivial** | Controller → one Service (no Operation) | Service <100 LOC | 1 service call, nothing to orchestrate |
| **Simple** | Controller → Operation → Services (Operation calls the services directly) | Operation <100 LOC | 2-4 service calls, straightforward sequence |
| **Medium** | Operation + extracted helper services | Operation ~150 LOC | 5-7 service calls, some conditionals |
| **Complex** | Operation + dedicated domain services (`@Transactional` stays on the services, guild #7) | Operation >150 LOC | 8+ calls, transactions, multi-step business logic |

**HITL Questions**:
1. How many service calls? (1, 2-4, 5-7, 8+)
2. Complex conditional logic between calls?
3. Multi-step transactions?
4. Reused from multiple controllers?
5. Permission checking + business logic + audit?

**Anti-Pattern**: Extra orchestration layer behind an Operation that just chains 3 service calls with no logic
```java
// ❌ Unnecessary layer — the Operation only forwards to another orchestrator
public class GetDataOperation {
    public Data execute() {
        return dataOrchestrationService.getData();
    }
}

public class DataOrchestrationService {
    public Data getData() {
        Data data = fetchService.fetch();
        enrichService.enrich(data);
        return mapperService.map(data);
    }
}

// ✅ Just do it in the one Operation the controller delegates to
public class GetDataOperation {
    public Data execute() {
        Data data = fetchService.fetch();
        enrichService.enrich(data);
        return mapperService.map(data);
    }
}
```

### Parameter Objects Decision

| Parameters | Validation | Reuse | Pattern |
|------------|------------|-------|---------|
| **1-3 simple** | None or basic null checks | Any | Inline with constants for defaults |
| **4 simple** | Basic null checks | 1-2 methods | Inline (borderline) |
| **4 simple** | Basic null checks | 3+ methods | Record parameter object |
| **5+ simple** | Any | Any | Record parameter object |
| **1-2 complex** | No cross-field rule | Any | Inline |
| **3+ complex** | Any | Any | Record parameter object |
| **Any count** | Cross-field validation | Any | Record parameter object |
| **Builder needed** (many optional params) | N/A | Any | Record with builder pattern |

Read the rows top-down; every combination of count, validation and reuse is covered.

**Anti-Pattern**: Record for 2 parameters
```java
// ❌ Overkill
public record SearchQuery(String term, boolean caseSensitive) {}

public List<Result> search(SearchQuery query) { ... }

// ✅ Use parameters directly (default from a constant via an overload)
public List<Result> search(String term) {
    return search(term, DEFAULT_CASE_SENSITIVE);
}

public List<Result> search(String term, boolean caseSensitive) {
    // ...
}
```

**When Records ARE Justified**:
- 5+ parameters (reduces parameter count)
- Cross-field validation (startDate < endDate)
- Immutable data containers
- Shared across 3+ methods

---

## HITL (Human-in-the-Loop) Checkpoints

### CRITICAL: Ask Before Applying Heavyweight Patterns

#### Before External-Client Pattern
**STOP and ASK**:
1. How many API endpoints/methods do you need **NOW**? (1-4, 5-9, 10+)
2. Is this simple REST CRUD or complex SDK integration?
3. Do you expect this to grow to 10+ endpoints in next 6 months?
4. Does query building involve complex DSL or just simple filters?
5. Is response parsing 1:1 JSON mapping or complex nested transformations?

**Decision Tree**:
```
└─ 1-4 simple CRUD endpoints?
   ├─ YES → Simple Wrapper (3 files)
   └─ NO
      └─ 5-9 endpoints with some complexity?
         ├─ YES → Lite Client (5 files)
         └─ NO
            └─ 10+ endpoints OR complex DSL?
               ├─ YES → Full 5-Layer (7-9 files)
               └─ NO → Start with Simple Wrapper, refactor when needed
```

#### Before Adding Layers Behind the Operation
**Ask only when the answer is not clear from the code** (otherwise apply the table above):
1. How many service calls does this use case orchestrate?
2. Is there complex permission checking + business logic + audit logging?
3. Are there multi-step transactions spanning multiple repositories?

**Decision** (the controller delegates to one `*Operation` when the use case orchestrates, otherwise to one `*Service`):
- 1 service call → the controller calls that one Service (no Operation)
- 2-4 simple service calls → one Operation calls the services directly (no extra orchestration layer)
- 5+ steps OR complex orchestration → split the Operation's work into focused helper / domain services

#### Before Parameter Objects
**Ask only when the table above is ambiguous** (e.g. 4 parameters with unclear reuse):
1. How many parameters does this method have?
2. Are there complex validation rules?
3. Is this parameter set shared across multiple methods?

**Decision**:
- 1-4 simple parameters → Inline with defaults from constants
- 5+ parameters OR complex validation → Record parameter objects

---

## When NOT to Ask (Prescriptive Decisions)

**Don't ask** for tool/library choices the catalogue prescribes:
- ❌ "Should we use Mockito or EasyMock?" → Mockito (prescribed)
- ❌ "Should we use @Value or @ConfigurationProperties?" → ConfigurationProperties (prescribed)
- ❌ "Should logs be JSON or plaintext?" → JSON (prescribed)

**DO ask** for scale/complexity decisions:
- ✅ "How many endpoints will this client have?"
- ✅ "Is this orchestration simple or complex?"
- ✅ "Do you expect significant growth?"

---

## Red Flags: You Might Be Over-Engineering If...

### 🚩 Warning Signs
1. **File count explosion**: Adding 1 feature creates 10+ files
2. **Deep directory nesting**: `client/dep/core/handler/request/builder/` (too many levels)
3. **Boilerplate dominance**: More infrastructure code than business logic
4. **Explaining takes >5 minutes**: Can't explain architecture simply to junior dev
5. **"Future-proofing" without requirements**: "What if we need..." without actual need
6. **Pattern stacking**: Applying multiple heavyweight patterns simultaneously

### ✅ Good Engineering Signs
1. **Proportional complexity**: Simple problems → simple solutions
2. **Clear purpose per file**: Each file does one obvious thing
3. **Easy navigation**: Can find relevant code in <30 seconds
4. **Simple explanation**: Can explain design in <3 minutes
5. **Actual requirements**: Solving real problems, not hypothetical ones

---

## The Refactoring Path (Start Simple → Add When Needed)

### Phase 1: Minimal Viable Structure
```
client/dep/
├── DepClient.java           # All-in-one RestClient wrapper
├── DepClientConfig.java     # Bean setup
└── DepProperties.java       # Config
```

### Phase 2: Extract When Pain Appears
**Add RequestBuilder when**:
- You've written similar URI-building code 3+ times
- Query building exceeds 10 lines per method
- Filters/params are shared across methods

**Add ResponseParser when**:
- Response extraction logic duplicated 3+ times
- Complex nested JSON transformations
- Multiple response formats to handle

**Add CoreService when**:
- Multiple request/response handlers exist
- Orchestration logic becomes complex
- Guard clauses spread across methods

### Phase 3: Full Pattern Only If Justified
**Promote to 5-layer when**:
- 10+ endpoints implemented
- Complex query DSL (Elasticsearch-style)
- Multi-step protocols over an SDK (for Kafka / RabbitMQ producers and consumers use `messaging`, not a client package)
- Heavy SDK abstraction needed

---

## Decision Criteria Cheat Sheet

| Question | Simple → Wrapper | Medium → Lite | Complex → Full 5-Layer |
|----------|------------------|---------------|------------------------|
| **How many endpoints?** | 1-4 | 5-9 | 10+ |
| **Query complexity?** | Simple params | Some filters | Complex DSL |
| **Response parsing?** | 1:1 JSON | Some mapping | Heavy transformation |
| **Growth expectation?** | Stable | Moderate | High |
| **Integration type?** | REST CRUD | REST with features | SDK/Protocol |

---

## Examples from Real World

### ✅ Appropriate Pattern Use

**Simple Wrapper** (health check proxy, basic lookup service):
```java
// 3 files, 250 LOC total
@Component
public class HealthCheckClient {
    private final RestClient restClient;
    private final HealthCheckProperties properties;

    public HealthCheckClient(@Qualifier("healthCheckRestClient") RestClient restClient, HealthCheckProperties properties) {
        this.restClient = restClient;
        this.properties = properties;
    }

    public boolean isHealthy() {
        try {
            HealthResponse health = restClient.get().uri(properties.healthEndpoint())
                .retrieve().body(HealthResponse.class);   // retrieve() throws on 4xx/5xx
            return health != null && "UP".equals(health.status());
        } catch (RestClientException e) {   // non-2xx status, timeout or I/O error
            return false;
        }
    }

    record HealthResponse(String status) {}
}
// HealthCheckClientConfig declares @Bean("healthCheckRestClient") from RestClient.Builder.clone() with connect and read
// timeouts from HealthCheckProperties — never call a dependency without timeouts, and never inject a per-dependency
// RestClient by type alone.
```

**Full 5-Layer** (Elasticsearch integration):
```
client/elasticsearch/                               # same layout as external-client §1
├── ElasticsearchService.java                       # facade: search(), aggregate(), scroll()
├── constant/
│   └── ElasticsearchConstants.java
├── core/
│   ├── ElasticsearchClientConfig.java              # transport bean
│   ├── ElasticsearchClient.java                    # thin transport wrapper
│   └── ElasticsearchCoreService.java               # orchestrates build → call → parse/verify
└── handler/
    ├── request/
    │   ├── ElasticsearchRequestBuilder.java         # DSL query + aggregation construction
    │   └── ElasticsearchFilterMapBuilder.java       # fluent filter composition
    └── response/
        ├── ElasticsearchResponseParser.java         # extract hits, scores, buckets
        └── ElasticsearchResponseVerifier.java       # hasHits, isSuccess…
```

### ❌ Over-Engineering Examples

**Simple CRUD with 5-layer pattern** (4 endpoints, GET/POST/PUT/DELETE):
- ❌ 9 files for simple operations
- ❌ RequestBuilder just builds `/api/resource/{id}` URIs
- ❌ ResponseParser just calls `objectMapper.readValue()`
- **Fix**: Use Simple Wrapper (3 files)

---

## Key Takeaways

1. **Complexity is a cost**: Every file/layer has maintenance burden
2. **YAGNI principle**: You Aren't Gonna Need It (until you actually do)
3. **Refactoring is normal**: Start simple, add complexity when justified
4. **Context over dogma**: Same pattern can be right or wrong depending on scale
5. **Ask when uncertain**: HITL for scale decisions prevents over-engineering

---

## Updated HITL Policy

### When to Ask Developer

**ALWAYS ask for**:
- External client scale (endpoints, complexity, growth)

**Ask only when ambiguous** (decide from the tables above when the code already answers it):
- Orchestration complexity (service count, transaction needs)
- Parameter object necessity (count, validation complexity)

**NEVER ask for**:
- Library choices (Mockito vs alternatives)
- Config approach (@Value vs @ConfigurationProperties)
- Logging format (JSON vs plaintext)

**Rule**: Ask about **scale and growth**, not about **prescribed choices**.

---

## Anti-Patterns to Avoid

### 1. Validation Redundancy (OpenAPI Duplication)

**Anti-Pattern**: Custom validator for what OpenAPI already validates

> **Applies only to the OpenAPI-first track** (`openapi-first-codegen`): the controller implements the
> generated interface, whose Bean Validation annotations enforce the schema at runtime — check the
> generated signature actually carries the constraint before dropping a validator. In **code-first**
> (springdoc) the spec is documentation only and validates nothing at runtime, so keep the Jakarta
> constraints and validators prescribed by `input-validation`.

```java
// ❌ Redundant - the generated interface already binds the $ref enum
@ValidOrderLayout  // Custom annotation
public String getOrders(@RequestParam String layout) { ... }

// api.yaml already has (enum as a $ref schema, so codegen emits a Java enum):
// layout:
//   $ref: '#/components/schemas/OrderLayout'
// components.schemas.OrderLayout:
//   type: string
//   enum: [all, metadata]
```

**What openapi-first codegen actually enforces** (with `useBeanValidation`):
- ✅ `required` (`@NotNull`), `pattern` (`@Pattern`), `minLength`/`maxLength` and `minItems`/`maxItems` (`@Size`),
  `minimum`/`maximum` (`@Min`/`@Max`/`@DecimalMin`/`@DecimalMax`).
- ✅ Enums declared as a `$ref` schema (generated Java enum — an unknown value fails binding).
- ✅ Formats that map to a Java type (e.g. `uuid` → `UUID`, `date` → `LocalDate`) — binding fails on bad input.
- ❌ **Inline** string enums on parameters usually stay `String` — not enforced.
- ❌ Most other `format`s (e.g. `hostname`, `ipv4`, custom formats) are documentation only.

When in doubt, read the generated signature: no annotation or type = no enforcement, keep the validator.

**Decision Tree**:
```
Is validation expressible in OpenAPI AND enforced by openapi-first generated code?
├─ YES ($ref enum, typed format, range, length, pattern, required — see the list above)
│  └─ Use OpenAPI schema ← NO custom validator
├─ Code-first (springdoc)?
│  └─ Use Jakarta Bean Validation (input-validation) — the spec is not enforced
└─ NO (cross-field, business rule, DB lookup)
   └─ Create custom Jakarta Bean Validation
```

**When Custom Validators ARE Needed**:
- ✅ Cross-field: `startDate < endDate`
- ✅ Business rules: `age >= 18 for account type`
- ✅ Database lookups: `userId exists`
- ✅ Complex regex beyond OpenAPI pattern
- ✅ Inline enums and formats the generator does not enforce (see the list above)
- ❌ Enum values declared as a `$ref` schema (OpenAPI handles — openapi-first only)
- ❌ Format validation for formats that map to a Java type (`uuid`, `date`, `date-time` — openapi-first only)
- ❌ Min/max ranges (OpenAPI handles — openapi-first only)

### 2. Thin Helper Service (Unnecessary Abstraction)

**Anti-Pattern**: Service with only 1-3 line wrapper methods

```java
// ❌ Thin helper - no real business logic
@Service
public class OrderService {
    
    public OrderLayout resolveLayout(String layout) {
        return OrderLayout.fromValue(layout != null ? layout : DEFAULT);
    }
    
    public ResponseDto createResponse(Layout layout, List<?> data) {
        return new ResponseDto(layout.getValue(), new ArrayList<>(data));
    }
}
```

**Service Smells**:
- All methods are 1-3 lines
- No injected dependencies (or only for delegation)
- No business logic or state
- Could be static utility methods
- Each method called from only 1 place

**When Service IS Justified**:
- ✅ Business logic (>10 LOC per method)
- ✅ State management (caching, pooling)
- ✅ Transactions
- ✅ Orchestrates 3+ repositories/clients
- ✅ Complex error handling
- ✅ Reused from 3+ places

**Fix**: Inline into the calling Operation (never the controller — it stays logic-free) or move to domain model
```java
// ✅ Better - inline into the Operation or domain method
public OrderLayout resolveLayout(String layout) {
    return OrderLayout.fromValue(layout != null ? layout : DEFAULT);
}
```

### 3. Unnecessary Delegation Layer

**Anti-Pattern**: Service that just calls one other service

```java
// ❌ Adds no value
@Service
@RequiredArgsConstructor
public class OrderFetchService {
    private final CatalogClient client;
    
    public List<Order> fetchOrders() {
        return client.getOrders();  // Just delegates
    }
}
```

**When Delegation IS Justified**:
- ✅ Adds filtering/transformation logic
- ✅ Orchestrates multiple sources
- ✅ Adds caching layer
- ✅ Permission checking
- ✅ Audit logging
- ✅ Error handling/retry

**Fix**: Call the client directly from the calling Operation or Service (never from the controller) or add real logic
```java
// ✅ Adds real value
public List<Order> fetchOpenOrders() {
    String token = authExtractor.extractToken();
    List<UUID> allowed = client.getVisibleCategoryIds(token);
    return allowed.stream()
        .flatMap(id -> client.getOrdersByCategory(id, token).stream())
        .filter(o -> o.getStatus().isOpen())
        .toList();
}
```

### 4. Over-Extracted Constants

**Anti-Pattern**: Constants file for 3-4 literals used in one class

```java
// ❌ Overkill
// file: constant/QueryConstants.java
public class QueryConstants {
    public static final String PARAM_CATEGORY_ID = "categoryId";
    public static final String PARAM_STATUS = "status";
}

// Used only in one class
client.get().uri(uri -> uri.queryParam(QueryConstants.PARAM_CATEGORY_ID, id))
```

**Decision**: Scope-based location

| Scope | Location |
|-------|----------|
| Used in 1 class only | `private static final` in that class |
| Used in 2-3 classes, same package | That package's `*Constants` class (or pass the value as a parameter) — never duplicated literals |
| Used across packages | Central `constant/` |
| API contract constants | Shared in `constant/` |
| Configuration property keys | `constant/ConfigurationConstants` (`code-structure`) |
| Exception messages | `exception/constants/ExceptionMessages` (`exception-handling`) |
| Shared vocabulary of one feature package (e.g. metric tag names) | That package's `*Constants` (e.g. `MonitoringConstants` in `request-metrics`) |

**Fix**: Keep constants close to usage
```java
// ✅ Better - private in the class
private static final String QUERY_PARAM_CATEGORY_ID = "categoryId";
```

### 5. Premature Abstraction (YAGNI Violation)

**Anti-Pattern**: Building for hypothetical future needs

```java
// ❌ "What if we need multiple layout strategies?"
// Creates handler + registry for 1 strategy

// ❌ "What if we need complex validation?"
// Creates validator framework for simple null check

// ❌ "What if we have 20 endpoints?"
// Builds 5-layer client for 2 endpoints
```

**YAGNI Principle**: You Aren't Gonna Need It

**Red Flags**:
- "What if..." without actual requirement
- "Future-proofing" without timeline
- "Enterprise-ready" for MVP
- Building frameworks for single use cases

**Fix**: Build for today, refactor when needed
```java
// ✅ Start simple
if (layout == null) layout = "detailed";   // same default as response-layout (DETAILED)

// Later, IF complexity grows:
// - 3+ layouts → Strategy pattern
// - Complex rules → Validator framework
// - 10+ endpoints → 5-layer client
```

---

**Last Updated**: 2026-07-13  
**Lesson Learned**: Over-engineering from literal pattern application without scale evaluation  
**Prevention**: HITL checkpoints for pattern selection based on actual complexity

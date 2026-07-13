# Pattern Selection Guide: Scale-Based Decision Making

**Purpose**: Prevent over-engineering by choosing patterns appropriate to actual scale and complexity.

**Key Principle**: **Start simple, add complexity when justified by actual needs.**

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

| Complexity | Pattern | LOC Threshold | Use When |
|------------|---------|---------------|----------|
| **Simple** | Controller → Services | Controller <100 LOC | 2-4 service calls, straightforward sequence |
| **Medium** | Optional Operation | Controller ~150 LOC | 5-7 service calls, some conditionals |
| **Complex** | Required Operation | Controller >150 LOC | 8+ calls, transactions, multi-step business logic |

**HITL Questions**:
1. How many service calls? (2-4, 5-7, 8+)
2. Complex conditional logic between calls?
3. Multi-step transactions?
4. Reused from multiple controllers?
5. Permission checking + business logic + audit?

**Anti-Pattern**: Operation that just chains 3 service calls with no logic
```java
// ❌ Unnecessary operation
public class GetDataOperation {
    public Data execute() {
        data = fetchService.fetch();
        enrichService.enrich(data);
        return mapperService.map(data);
    }
}

// ✅ Just do it in controller
public Data getData() {
    Data data = fetchService.fetch();
    enrichService.enrich(data);
    return mapperService.map(data);
}
```

### Parameter Objects Decision

| Parameters | Validation | Reuse | Pattern |
|------------|------------|-------|---------|
| **1-3 simple** | None | 1-2 methods | Inline with constants for defaults |
| **4 simple** | Basic null checks | 1-2 methods | Inline (borderline) |
| **5+ simple** | Any | Multiple | Record parameter object |
| **3+ complex** | Cross-field validation | Any | Record parameter object |
| **Builder needed** | N/A | Any | Record with builder pattern |

**Anti-Pattern**: Record for 2 parameters
```java
// ❌ Overkill
public record SearchQuery(String term, boolean caseSensitive) {}

public List<Result> search(SearchQuery query) { ... }

// ✅ Use parameters directly
public List<Result> search(String term, boolean caseSensitive) {
    caseSensitive = caseSensitive || DEFAULT_CASE_SENSITIVE;
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

#### Before Operation Layer
**STOP and ASK**:
1. How many service calls does this controller method orchestrate?
2. Is there complex permission checking + business logic + audit logging?
3. Are there multi-step transactions spanning multiple repositories?

**Decision**:
- 2-4 simple service calls → Controller calls services directly
- 5+ steps OR complex orchestration → Operation layer

#### Before Parameter Objects
**STOP and ASK**:
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
- Multi-step protocols (Kafka patterns)
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
    
    public boolean isHealthy() {
        return restClient.get().uri(properties.healthEndpoint())
            .retrieve().body(String.class).contains("UP");
    }
}
```

**Full 5-Layer** (Elasticsearch integration):
```
client/elasticsearch/
├── ElasticsearchService.java           # search(), aggregate(), scroll()
├── core/
│   ├── ElasticsearchCoreService.java   # orchestrates query building
│   └── ElasticsearchClient.java        # thin HTTP wrapper
├── handler/
│   ├── request/
│   │   ├── QueryBuilder.java           # DSL query construction
│   │   └── AggregationBuilder.java     # complex aggregations
│   └── response/
│       ├── SearchResponseParser.java   # extract hits, scores
│       └── AggregationParser.java      # parse buckets
└── constant/ElasticsearchConstants.java
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
- Orchestration complexity (service count, transaction needs)
- Parameter object necessity (count, validation complexity)

**NEVER ask for**:
- Library choices (Mockito vs alternatives)
- Config approach (@Value vs @ConfigurationProperties)
- Logging format (JSON vs plaintext)

**Rule**: Ask about **scale and growth**, not about **prescribed choices**.

---

---

## Anti-Patterns to Avoid

### 1. Validation Redundancy (OpenAPI Duplication)

**Anti-Pattern**: Custom validator for what OpenAPI already validates

```java
// ❌ Redundant - OpenAPI already validates enum
@ValidWorkflowLayout  // Custom annotation
public String getWorkflows(@RequestParam String layout) { ... }

// api.yaml already has:
// layout:
//   type: string
//   enum: [all, metadata]
```

**Decision Tree**:
```
Is validation expressible in OpenAPI?
├─ YES (enum, format, range, pattern, required)
│  └─ Use OpenAPI schema ← NO custom validator
└─ NO (cross-field, business rule, DB lookup)
   └─ Create custom Jakarta Bean Validation
```

**When Custom Validators ARE Needed**:
- ✅ Cross-field: `startDate < endDate`
- ✅ Business rules: `age >= 18 for account type`
- ✅ Database lookups: `userId exists`
- ✅ Complex regex beyond OpenAPI pattern
- ❌ Enum values (OpenAPI handles)
- ❌ Format validation (OpenAPI has email, uri, date, etc.)
- ❌ Min/max ranges (OpenAPI handles)

### 2. Thin Helper Service (Unnecessary Abstraction)

**Anti-Pattern**: Service with only 1-3 line wrapper methods

```java
// ❌ Thin helper - no real business logic
@Service
public class WorkflowService {
    
    public MissionLayout resolveLayout(String layout) {
        return MissionLayout.fromValue(layout != null ? layout : DEFAULT);
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

**Fix**: Inline to controller or move to domain model
```java
// ✅ Better - inline or domain method
public MissionLayout resolveLayout(String layout) {
    return MissionLayout.fromValue(layout != null ? layout : DEFAULT);
}
```

### 3. Unnecessary Delegation Layer

**Anti-Pattern**: Service that just calls one other service

```java
// ❌ Adds no value
@Service
public class MissionFetchService {
    private final DbManagementClient client;
    
    public List<Mission> fetchMissions() {
        return client.getMissions();  // Just delegates
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

**Fix**: Call client directly or add real logic
```java
// ✅ Adds real value
public List<Mission> fetchRunningMissions() {
    String token = authExtractor.extractToken();
    List<UUID> allowed = client.getAllowedTemplateIds(token);
    return allowed.stream()
        .flatMap(id -> client.getMissionsByTemplate(id, token).stream())
        .filter(m -> m.getStatus().isRunning())
        .toList();
}
```

### 4. Over-Extracted Constants

**Anti-Pattern**: Constants file for 3-4 literals used in one class

```java
// ❌ Overkill
// file: constant/QueryConstants.java
public class QueryConstants {
    public static final String PARAM_TEMPLATE_ID = "templateId";
    public static final String PARAM_STATUS = "status";
}

// Used only in one class
client.get().uri(uri -> uri.queryParam(QueryConstants.PARAM_TEMPLATE_ID, id))
```

**Decision**: Scope-based location

| Scope | Location |
|-------|----------|
| Used in 1 class only | `private static final` in that class |
| Used in 2-3 classes, same package | Inline or pass as parameter |
| Used across packages | Central `constant/` |
| API contract constants | Shared in `constant/` |

**Fix**: Keep constants close to usage
```java
// ✅ Better - private in the class
private static final String QUERY_PARAM_TEMPLATE_ID = "templateId";
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
if (layout == null) layout = "all";

// Later, IF complexity grows:
// - 3+ layouts → Strategy pattern
// - Complex rules → Validator framework
// - 10+ endpoints → 5-layer client
```

---

**Last Updated**: 2026-07-13  
**Lesson Learned**: Over-engineering from literal pattern application without scale evaluation  
**Prevention**: HITL checkpoints for pattern selection based on actual complexity

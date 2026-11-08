# this Code Structure Skill — Patterns A–D

Part of the [`code-structure`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 2. Pattern A — Strategy + Handler (used in `permission/`, `renderer/`, `layout/`, `mapper/`)

> **Foundational Pattern:** This is an application of the `strategy-registry-pattern` skill.
> Read that skill for the complete pattern definition and all component responsibilities.

When the same operation has **multiple interchangeable implementations** chosen
at runtime, use this pattern:

1. **`<X>Strategy`** – interface with a `supports(...)` / `canHandle(...)` method plus the business method
2. **Concrete strategies** – `@Component` classes implementing the interface
3. **`<X>Registry`** – `@Component` that receives `List<<X>Strategy>` via constructor injection and routes by calling `canHandle`
4. **`<X>Handler`** – orchestrator that resolves context, calls registry, executes strategy

**Reference implementations in this repo:**
- `permission/` — PermissionsCheckStrategy + PermissionsHandler (see permissions)
- `monitor/` — MetricsRecorder + MetricsRecorderRegistry (see request-metrics)
- `layout/` — LayoutStrategy + LayoutHandler (see response-layout)
- `mapper/` — MapperStrategy + MapperHandler (see response-mapper)

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class XyzHandler {
    private final List<XyzStrategy> strategies;

    public Result handle(Input in) {
        return strategies.stream()
                .filter(s -> s.supports(in))
                .findFirst()
                .orElseThrow(() -> new DomainException(...))
                .execute(in);
    }
}
```

**Reference implementations in this repo:**
- `permission/PermissionsCheckStrategy` + `PermissionsHandler`
- `renderer/FooRenderer` + `renderer/registry/ExportRendererRegistry`

### Do / Don't
✅ Add a new behaviour by adding **one** new `@Component` strategy – never touch
the handler.
✅ Throw a domain exception (extends `RuntimeException` or `Exception` from
`exception/`) when no strategy matches.
❌ Do not `if/else` on a type discriminator inside a service – that is a smell
indicating you should introduce a strategy.

## 3. Pattern B — Metrics Filter + Recorder Registry (used in `monitor/`)

> **Foundational Pattern:** This is a **Filter-based variation** of the `strategy-registry-pattern` skill.
> Read that skill for the complete pattern definition. This section covers the filter-specific aspects.

For request-level observability use a single `OncePerRequestFilter` that
delegates to a **recorder** chosen by a registry, plus pluggable **parsers**
that extract tags from the request/response.

Full implementation details in request-metrics skill.

```
monitor/
├── MetricsFilter.java          # OncePerRequestFilter – measures latency
├── MonitoringConfig.java       # @Configuration: URI Pattern → query type
├── MonitoringConstants.java
├── MetricsTagsHelper.java
├── MetricsTimerHelper.java
├── parsers/                    # one parser per tag (ClientId, ExportFormat, …)
└── recorder/
    ├── MetricsRecorder.java            # interface: recordMetrics(durationMs, req, res)
    ├── MetricsRecorderRegistry.java    # maps queryType → MetricsRecorder
    └── <UseCase>MetricsRecorder.java   # one per business use case
```

Rules:

- The filter measures **elapsed time** in a `try/finally` so failures are still
  recorded.
- Skip `actuator` URIs in `shouldNotFilter`.
- Tag names live in `MonitoringConstants`; do not inline string literals.
- A new metric = **new recorder + new parser** if needed; the filter never changes.

## 4. Pattern C — Operation / Service split

Each public REST endpoint maps to exactly one class in `operation/`:

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class ExportInvoiceOperation {
    private final PermissionsHandler permissionsHandler;
    private final ExportInvoiceService exportInvoiceService;

    public ExportInvoiceResponse execute(ExportInvoiceRequest req) {
        permissionsHandler.handle(req.invoiceId(), req.attachmentId());
        return exportInvoiceService.export(req);
    }
}
```

- Controllers only do: validate input → call `operation.execute(...)` → map response.
- Services do **one** thing each; compose them inside an operation.

## 4k. Pattern D — Monolith to Module

For larger services that are not yet ready for microservices, use **Spring Modulith** or strict package-level isolation to prevent the "Big Ball of Mud".

1. **Modules by package**: `com.example.service.moduleA`, `com.example.service.moduleB`.
2. **Encapsulation**: Only the `api/` sub-package of a module is public. Everything else is package-private.
3. **Internal events**: Use Spring `ApplicationEventPublisher` to communicate between modules. Module A publishes `OrderCreated`, Module B listens. No direct service-to-service calls across module boundaries.

This makes future extraction into a separate microservice trivial.

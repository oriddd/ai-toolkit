# Code Structure — Patterns A–D

Part of the [`code-structure`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 2. Pattern A — Strategy + Handler (used in `permission/`, `renderer/`, `layout/`, `mapper/`)

> **Foundational Pattern:** This is an application of the `strategy-registry-pattern` skill.
> Read that skill for the complete pattern definition and all component responsibilities.

When the same operation has **multiple interchangeable implementations** chosen
at runtime, use this pattern:

1. **`<X>Strategy`** – interface with a `canHandle(...)` discriminator method plus the business method
2. **Concrete strategies** – `@Component` classes implementing the interface
3. **`<X>Registry`** – `@Component` that receives `List<<X>Strategy>` via constructor injection and routes by calling `canHandle`
4. **`<X>Handler`** – orchestrator that resolves context, calls registry, executes strategy

**Reference skills:**
- `permission/` — PermissionsCheckStrategy + PermissionsHandler (see `permissions`)
- `monitor/` — MetricsRecorder + MetricsRecorderRegistry (see `request-metrics`)
- `layout/` — LayoutStrategy + LayoutHandler (see `response-layout`; `layout/` is a feature package in §1)
- `mapper/` — MapperStrategy + MapperHandler (see `response-mapper`)
- `renderer/` — `InvoicePdfRenderer` … + `renderer/registry/ExportRendererRegistry`

```java
@Component
@RequiredArgsConstructor
public class XyzHandler {
    private final List<XyzStrategy> strategies;

    public Result handle(Input in) {
        List<XyzStrategy> matches = strategies.stream()
                .filter(s -> s.canHandle(in))
                .toList();
        if (matches.size() > 1) {   // routing must never depend on bean order
            throw new IllegalStateException("Ambiguous XyzStrategy for " + in + ": " + matches);
        }
        return matches.stream()
                .findFirst()
                .orElseThrow(() -> new DomainException(...))
                .execute(in);
    }
}
```

### Do / Don't
✅ Add a new behaviour by adding **one** new `@Component` strategy – never touch
the handler.
✅ Throw a domain exception (unchecked — extends the `RuntimeException`-based
hierarchy in `exception/`) when no strategy matches.
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
├── parser/                     # one parser per tag (ClientId, ExportFormat, …)
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
- A new metric = **new `MonitoringConfig` URI-pattern entry + new recorder + new
  parser** if needed (guild #24); the filter never changes.

## 4. Pattern C — Operation / Service split

Each public REST endpoint that orchestrates a use case (permission check,
several services, response assembly) maps to exactly one class in
`operation/`; an endpoint that orchestrates nothing calls exactly one
`*Service` instead (guild rule 3, SKILL §1c):

```java
@Component
@RequiredArgsConstructor
public class ExportInvoiceOperation {
    private final PermissionsHandler permissionsHandler;
    private final ExportInvoiceService exportInvoiceService;

    public ExportInvoiceResponse execute(ExportInvoiceRequest req) {
        permissionsHandler.handle(req.invoiceId());   // throws the unchecked ForbiddenException
        return exportInvoiceService.export(req);
    }
}
```

- Controllers only do: trigger `@Valid` (the validation layer owns the rules) → call `operation.execute(...)` → map response.
- Services do **one** thing each; compose them inside an operation.

## 4k. Pattern D — Monolith to Module

For larger services that are not yet ready for microservices, use **Spring Modulith** or strict package-level isolation to prevent the "Big Ball of Mud".

1. **Modules by package**: `com.example.service.moduleA`, `com.example.service.moduleB` — each direct sub-package of the application package is one module.
2. **Encapsulation**: A module's **base package is its API**; everything in its sub-packages (e.g. `moduleA.internal`) is internal and must not be used by other modules. With strict package-level isolation (no Modulith), keep internals package-private. (Use `@NamedInterface` to expose an extra sub-package deliberately.)
3. **Internal events**: Use Spring `ApplicationEventPublisher` to communicate between modules. Module A publishes `OrderCreated`, Module B listens. No direct service-to-service calls across module boundaries.
   - With Spring Modulith, listen with `@ApplicationModuleListener` (async, after commit, in its own transaction) and enable the **event publication registry** (`spring-modulith-starter-jpa` or `-jdbc`) so unfinished events survive a crash and are resubmitted. A plain `@EventListener` is synchronous and gives no durability.
4. **Verify**: add a test calling `ApplicationModules.of(<App>.class).verify()` so illegal cross-module access and cycles fail the build.

This makes future extraction into a separate microservice trivial.

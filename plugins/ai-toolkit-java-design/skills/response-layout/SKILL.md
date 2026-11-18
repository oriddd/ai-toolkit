---
name: response-layout
description: >
  Java / Spring Boot ?layout= parameter (summary/detailed/full) via Strategy + Handler + Registry — one LayoutStrategy
  per field set. Use when an endpoint must return different field sets on request. For API versions or projections use
  `response-mapper`.
tier: should
applies_to: [rest, monolith]
depends_on: [code-structure, spring-boot-conventions, strategy-registry-pattern]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-15
---

# Response Layout Skill
> **Pattern Foundation:** This skill is a concrete application of the strategy-registry-pattern skill. 
> Read that skill first to understand the foundational pattern, then return here for the layout-specific implementation.

Many REST endpoints need to return different field sets based on the client's needs:
- **Summary** — minimal fields for list views
- **Detailed** — standard field set for single-item views
- **Full** — all fields including computed/expensive data

This skill provisions a **layout-based response mapping** layer using the Strategy + Handler + Registry pattern. 
Clients request a layout via `?layout=summary` (or detailed/full), and the endpoint returns a tailored DTO.

> **Pattern Application:** This follows the **Handler-based variation** of the strategy-registry-pattern.
> Components: Handler → Resolver (LayoutType from query param) → Registry → Strategy (entity→DTO mapping)

## 1. Package structure

```
layout/
├── LayoutType.java                    # enum: SUMMARY / DETAILED / FULL
├── LayoutConstants.java               # layout names as constants
├── LayoutResolver.java                # Resolver: extracts ?layout=X from request
├── LayoutStrategy.java                # Strategy interface: defines map(entity) contract
├── LayoutHandler.java                 # Handler: orchestrates resolver → registry → strategy
├── LayoutRegistry.java                # Registry: routes (entity type, LayoutType) → strategy
├── LayoutAccessPolicy.java            # Port: may this caller see a restricted layout? (implemented in permission/)
└── strategy/
    ├── SummaryLayoutStrategy.java     # Strategy: entity → SummaryDTO
    ├── DetailedLayoutStrategy.java    # Strategy: entity → DetailedDTO
    └── FullLayoutStrategy.java        # Strategy: entity → FullDTO
```

## 2. Pattern Components

See strategy-registry-pattern for detailed component responsibilities.

**Layout-specific mapping:**
- **Discriminator:** `LayoutType` enum (SUMMARY / DETAILED / FULL)
- **Resolver:** Reads `?layout=X` query parameter; an unknown value is a 400, never a silent fallback
- **Strategy:** Maps entity → DTO for the specific layout; says whether the layout is restricted
- **Handler:** Orchestrates resolver → registry → access check → strategy, returns DTO

**Layouts are not field-level security.** Any caller can send `?layout=full`. A layout that exposes sensitive or
internal data (permissions, change history, audit data) is **restricted**: the handler asks `LayoutAccessPolicy`
first and answers 403 when the caller may not see it.

## 3. Implementation

### `LayoutType` (enum)

```java
public enum LayoutType {
    SUMMARY, DETAILED, FULL;

    public static LayoutType fromString(final String layout) throws BadRequestException {
        if (layout == null || layout.isBlank()) {
            return DETAILED;  // default when the client sends no layout
        }
        try {
            return LayoutType.valueOf(layout.trim().toUpperCase(Locale.ROOT));   // Locale.ROOT: "full" must not depend on the server locale
        } catch (final IllegalArgumentException e) {
            // an unknown layout is a client error (400), never a silent fallback to DETAILED
            throw ExceptionMessages.invalidField("layout", "expected one of " + Arrays.toString(values()));
        }
    }
}
```

`ExceptionMessages.invalidField` returns the `BadRequestException` of `exception-handling` (400). With
openapi-first, declare `layout` as a `$ref` enum in `api.yaml` instead (an inline `enum:` is generated as a plain
`String` that accepts anything) and set the generator's `configPackage` inside the scan (`openapi-first-codegen` §1, §2),
so an unknown value is rejected before the handler runs.

### `LayoutResolver`

```java
@Component
public class LayoutResolver {
    public LayoutType resolve(final HttpServletRequest request) throws BadRequestException {
        if (request == null) {
            return LayoutType.DETAILED;
        }
        final String layoutParam = request.getParameter("layout");
        return LayoutType.fromString(layoutParam);
    }
}
```

### `LayoutStrategy` (interface)

```java
public interface LayoutStrategy<E, D> {
    @Nullable D map(@Nullable E entity);
    LayoutType getSupportedLayoutType();
    Class<E> getEntityType();   // the registry is shared by every entity — this keeps Product and other entities apart

    /** A restricted layout exposes sensitive or internal fields; the handler checks LayoutAccessPolicy first. */
    default boolean isRestricted() {
        return false;
    }

    default boolean canHandle(final LayoutType layoutType) {
        return getSupportedLayoutType() != null 
                && getSupportedLayoutType().equals(layoutType);
    }
}
```

### `LayoutAccessPolicy` (port)

```java
/** Implemented in permission/ (it may read the security context); layout/ only depends on this interface. */
public interface LayoutAccessPolicy {
    boolean isAllowed(LayoutType layoutType, String resourceId);
}
```

### `LayoutRegistry`

One **non-generic** singleton for every entity. Spring injects every `LayoutStrategy` (Product, Order, …) and `find`
routes by the entity type and `canHandle(layoutType)`. The constructor checks the declared (entity type, layout)
pairs and fails at startup when two strategies claim the same pair. The generic type is restored in one place,
`find(...)`, where the entity-type match guarantees it.

```java
@Component
public class LayoutRegistry {
    private record Key(Class<?> entityType, LayoutType layoutType) { }

    private final List<LayoutStrategy<?, ?>> strategies;

    public LayoutRegistry(final List<LayoutStrategy<?, ?>> strategies) {
        final Map<Key, LayoutStrategy<?, ?>> declared = new HashMap<>();
        for (final LayoutStrategy<?, ?> strategy : strategies) {
            final LayoutStrategy<?, ?> first =
                    declared.putIfAbsent(new Key(strategy.getEntityType(), strategy.getSupportedLayoutType()), strategy);
            if (first != null) {
                throw new IllegalStateException("Two layout strategies for " + strategy.getEntityType().getSimpleName()
                        + "/" + strategy.getSupportedLayoutType() + ": " + first.getClass().getName()
                        + ", " + strategy.getClass().getName());
            }
        }
        this.strategies = List.copyOf(strategies);
    }

    @SuppressWarnings("unchecked")   // safe: the strategy's own getEntityType() equals entityType
    public <E> @Nullable LayoutStrategy<E, ?> find(final Class<E> entityType, final LayoutType layoutType) {
        return (LayoutStrategy<E, ?>) strategies.stream()
                .filter(s -> s.getEntityType().equals(entityType) && s.canHandle(layoutType))
                .findFirst()
                .orElse(null);
    }
}
```

### `LayoutHandler`

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class LayoutHandler {
    private final LayoutResolver layoutResolver;
    private final LayoutRegistry layoutRegistry;
    private final LayoutAccessPolicy layoutAccessPolicy;

    /**
     * @param entityType passed explicitly — entity.getClass() can be a JPA proxy subclass
     * @param resourceId the id the access policy checks for restricted layouts
     * @param entity     not null in practice: the service already threw NotFoundException (404) for a missing resource
     */
    public <E> @Nullable Object handle(final Class<E> entityType, final String resourceId, final E entity,
                             final HttpServletRequest request) throws BaseDomainException {
        final LayoutType layoutType = layoutResolver.resolve(request);   // unknown value → 400
        final LayoutStrategy<E, ?> strategy = layoutRegistry.find(entityType, layoutType);
        if (strategy == null) {
            if (layoutType == LayoutType.DETAILED) {   // the default layout is mandatory for every entity
                throw new IllegalStateException("No DETAILED layout strategy for " + entityType.getSimpleName() + " (mandatory)");
            }
            // a valid layout this entity does not offer is a client error (400), never a silent fallback to DETAILED
            throw ExceptionMessages.invalidField("layout", layoutType + " is not available for " + entityType.getSimpleName());
        }

        if (strategy.isRestricted() && !layoutAccessPolicy.isAllowed(strategy.getSupportedLayoutType(), resourceId)) {
            throw ExceptionMessages.accessDenied("layout " + strategy.getSupportedLayoutType());   // 403
        }
        return strategy.map(entity);
    }
}
```

### Concrete Strategies

One `@Component` per (entity, layout): summary, detailed (the mandatory default) and full (restricted) — load
[`references/concrete-strategies.md`](./references/concrete-strategies.md) for the implementations. Every strategy
starts `map` with `if (entity == null) return null;`.

## 4. Controller Integration

```java
@RestController
@RequestMapping("/api/v1/products")
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class ProductController {
    private final ProductService productService;
    private final LayoutHandler layoutHandler;

    @GetMapping("/{id}")
    @ApiResponse(responseCode = "200", content = @Content(schema = @Schema(oneOf = {
            ProductSummaryDTO.class, ProductDetailedDTO.class, ProductFullDTO.class })))
    public ResponseEntity<Object> getProduct(@PathVariable final String id,
                                             final HttpServletRequest request) throws BaseDomainException {
        final Product product = productService.getById(id);
        final Object dto = layoutHandler.handle(Product.class, id, product, request);
        return ResponseEntity.ok(dto);
    }
}
```

**Rules:**
- The response type is `Object` — the handler returns the right DTO based on layout. Without the `oneOf`
  `@ApiResponse` springdoc publishes no schema, so declare every layout DTO there.
- **openapi-first:** a generated `ProductApi` method has one fixed return type, so this controller cannot implement it
  as is. Declare the layouts as `oneOf` in `api.yaml` and map to the generated types, or don't use layouts there.
- Pass `HttpServletRequest` to handler for layout resolution
- Service returns **product**, mapping is presentation-layer concern
- Unknown `?layout=`, or a layout this entity has no strategy for → 400 (no silent fallback); a restricted layout
  the caller may not see → 403. No `?layout=` → `DETAILED`, which every entity must provide

## 5. Adding a New Layout

**Checklist:**
1. ✅ Add new `LayoutType` enum value (e.g., `COMPACT`, `MOBILE`)
2. ✅ Create new DTO class (e.g., `ProductCompactDTO`)
3. ✅ Create new `<Layout>LayoutStrategy implements LayoutStrategy`
4. ✅ Make it a `@Component`
5. ✅ Implement `getSupportedLayoutType()`, `getEntityType()` and `map(entity)` (it inherits `canHandle`); override `isRestricted()` to `true`
   when the layout exposes sensitive or internal data
6. ✅ Write unit tests, including the null-entity guard and the 403 path for a restricted layout ([`references/testing.md`](./references/testing.md))

**Zero changes needed:**
- ❌ LayoutHandler, LayoutRegistry, LayoutResolver, existing strategies (a second strategy for the same entity and
  layout fails the startup — replace the existing one instead)

## 6. When to Use

✅ **Use when:**
- Endpoints must return different field sets (summary/detailed/full)
- Mobile clients need compact responses, web clients need full data
- Performance optimization — avoid sending unused fields
- Multi-tenant scenarios with different field presentation — not as field-level security: hiding data from a
  caller always needs an authorization check (restricted layouts, §7 "Layout + Permissions")

❌ **Don't use when:**
- Only one response shape needed — use single DTO
- Field differences minimal (1-2 fields) — use `@JsonInclude`/`@JsonView`
- Layout determined at compile-time — use separate endpoints

## 7. Variations

Layout + Permissions (field filtering by a boolean permission query) and layout from the `Accept` header — load [`references/variations.md`](./references/variations.md) when you need one of them.

---

**Version:** 1.0  
**Last Reviewed:** 2026-11-15

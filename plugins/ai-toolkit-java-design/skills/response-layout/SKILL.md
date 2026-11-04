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
last_reviewed: 2026-07-12
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
├── LayoutRegistry.java                # Registry: routes LayoutType → strategy
└── strategy/
    ├── SummaryLayoutStrategy.java     # Strategy: entity → SummaryDTO
    ├── DetailedLayoutStrategy.java    # Strategy: entity → DetailedDTO
    └── FullLayoutStrategy.java        # Strategy: entity → FullDTO
```

## 2. Pattern Components

See strategy-registry-pattern for detailed component responsibilities.

**Layout-specific mapping:**
- **Discriminator:** `LayoutType` enum (SUMMARY / DETAILED / FULL)
- **Resolver:** Reads `?layout=X` query parameter
- **Strategy:** Maps entity → DTO for the specific layout
- **Handler:** Orchestrates resolver → registry → strategy, returns DTO

## 3. Implementation

### `LayoutType` (enum)

```java
public enum LayoutType {
    SUMMARY, DETAILED, FULL;

    public static LayoutType fromString(final String layout) {
        if (StringUtils.isBlank(layout)) {
            return DETAILED;  // default
        }
        try {
            return LayoutType.valueOf(layout.toUpperCase());
        } catch (final IllegalArgumentException e) {
            return DETAILED;  // fallback
        }
    }
}
```

### `LayoutResolver`

```java
@Component
public class LayoutResolver {
    public LayoutType resolve(final HttpServletRequest request) {
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
    D map(E entity);
    LayoutType getSupportedLayoutType();

    default boolean canHandle(final LayoutType layoutType) {
        return getSupportedLayoutType() != null 
                && getSupportedLayoutType().equals(layoutType);
    }
}
```

### `LayoutRegistry`

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class LayoutRegistry<E, D> {
    private final List<LayoutStrategy<E, D>> strategies;

    public LayoutStrategy<E, D> getStrategy(final LayoutType layoutType) {
        return strategies.stream()
                .filter(s -> s.canHandle(layoutType))
                .findFirst()
                .orElse(null);
    }
}
```

### `LayoutHandler`

```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
@Slf4j
public class LayoutHandler<E, D> {
    private final LayoutResolver layoutResolver;
    private final LayoutRegistry<E, D> layoutRegistry;

    public D handle(final E entity, final HttpServletRequest request) {
        final LayoutType layoutType = layoutResolver.resolve(request);
        final LayoutStrategy<E, D> strategy = layoutRegistry.getStrategy(layoutType);

        if (strategy == null) {
            log.warn("No layout strategy found for type: {}, using DETAILED", layoutType);
            final LayoutStrategy<E, D> fallback = layoutRegistry.getStrategy(LayoutType.DETAILED);
            if (fallback == null) {
                throw new IllegalStateException("No DETAILED layout strategy found (mandatory)");
            }
            return fallback.map(entity);
        }

        return strategy.map(entity);
    }
}
```

### Concrete Strategies

**SummaryLayoutStrategy** — minimal fields:
```java
@Component
public class ProductSummaryLayoutStrategy implements LayoutStrategy<Product, ProductSummaryDTO> {
    @Override
    public LayoutType getSupportedLayoutType() {
        return LayoutType.SUMMARY;
    }

    @Override
    public ProductSummaryDTO map(final Product product) {
        if (product == null) return null;
        return ProductSummaryDTO.builder()
                .id(product.getId())
                .name(product.getName())
                .createdAt(product.getCreatedAt())
                .build();
    }
}
```

**DetailedLayoutStrategy** — standard fields (mandatory default):
```java
@Component
public class ProductDetailedLayoutStrategy implements LayoutStrategy<Product, ProductDetailedDTO> {
    @Override
    public LayoutType getSupportedLayoutType() {
        return LayoutType.DETAILED;
    }

    @Override
    public ProductDetailedDTO map(final Product product) {
        if (product == null) return null;
        return ProductDetailedDTO.builder()
                .id(product.getId())
                .name(product.getName())
                .description(product.getDescription())
                .createdAt(product.getCreatedAt())
                .updatedAt(product.getUpdatedAt())
                .owner(product.getOwner())
                .build();
    }
}
```

**FullLayoutStrategy** — all fields + expensive computations:
```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class ProductFullLayoutStrategy implements LayoutStrategy<Product, ProductFullDTO> {
    private final ProductMetadataService productMetadataService;

    @Override
    public LayoutType getSupportedLayoutType() {
        return LayoutType.FULL;
    }

    @Override
    public ProductFullDTO map(final Product product) {
        if (product == null) return null;
        return ProductFullDTO.builder()
                .id(product.getId())
                .name(product.getName())
                .description(product.getDescription())
                .createdAt(product.getCreatedAt())
                .updatedAt(product.getUpdatedAt())
                .owner(product.getOwner())
                // Full layout includes expensive/computed fields
                .metadata(productMetadataService.getMetadataFor(product.getId()))
                .permissions(product.getPermissions())
                .changeHistory(product.getChangeHistory())
                .build();
    }
}
```

## 4. Controller Integration

```java
@RestController
@RequestMapping("/api/v1/products")
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class ProductController {
    private final ProductService productService;
    private final LayoutHandler<Product, ?> layoutHandler;

    @GetMapping("/{id}")
    public ResponseEntity<?> getProduct(@PathVariable final String id,
                                       final HttpServletRequest request) {
        final Product product = productService.getById(id);
        final Object dto = layoutHandler.handle(product, request);
        return ResponseEntity.ok(dto);
    }
}
```

**Rules:**
- Wildcard `?` for DTO type — handler returns the right DTO based on layout
- Pass `HttpServletRequest` to handler for layout resolution
- Service returns **product**, mapping is presentation-layer concern

## 5. Adding a New Layout

**Checklist:**
1. ✅ Add new `LayoutType` enum value (e.g., `COMPACT`, `MOBILE`)
2. ✅ Create new DTO class (e.g., `ProductCompactDTO`)
3. ✅ Create new `<Layout>LayoutStrategy implements LayoutStrategy`
4. ✅ Make it a `@Component`
5. ✅ Implement `getSupportedLayoutType()` and `map(entity)`
6. ✅ Write unit tests

**Zero changes needed:**
- ❌ LayoutHandler, LayoutRegistry, LayoutResolver, existing strategies

## 6. When to Use

✅ **Use when:**
- Endpoints must return different field sets (summary/detailed/full)
- Mobile clients need compact responses, web clients need full data
- Performance optimization — avoid sending unused fields
- Multi-tenant scenarios with different field visibility

❌ **Don't use when:**
- Only one response shape needed — use single DTO
- Field differences minimal (1-2 fields) — use `@JsonInclude`/`@JsonView`
- Layout determined at compile-time — use separate endpoints

## 7. Variations

### Layout + Permissions
Filter fields based on caller permissions:
```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class SecureFullLayoutStrategy implements LayoutStrategy<Product, ProductFullDTO> {
    private final PermissionsHandler permissionsHandler;

    @Override
    public ProductFullDTO map(final Product product) {
        final ProductFullDTO dto = /* base mapping */;
        try {
            permissionsHandler.handle(product.getId());
            dto.setSensitiveData(product.getSensitiveData());
        } catch (final ForbiddenException e) {
            // Omit sensitive fields
        }
        return dto;
    }
}
```

### Layout from Accept Header
Use media type instead of query param:
```java
@Component
public class LayoutResolver {
    public LayoutType resolve(final HttpServletRequest request) {
        final String accept = request.getHeader("Accept");
        if (accept != null && accept.contains("application/vnd.api.summary+json")) {
            return LayoutType.SUMMARY;
        }
        return LayoutType.DETAILED;
    }
}
```

---

**Version:** 1.0  
**Last Reviewed:** 2026-07-12

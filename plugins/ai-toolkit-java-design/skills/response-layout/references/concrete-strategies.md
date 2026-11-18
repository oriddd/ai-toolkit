# Response Layout Skill — Concrete strategies

Part of the [`response-layout`](../SKILL.md) skill (§3, Implementation). Headings are stable; other skills cite them.

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
    public Class<Product> getEntityType() {
        return Product.class;
    }

    @Override
    public @Nullable ProductSummaryDTO map(final @Nullable Product product) {
        if (product == null) return null;
        return new ProductSummaryDTO(product.getId(), product.getName(), product.getCreatedAt());
    }
}

// DTOs are immutable records (`code-structure`: models are records)
public record ProductSummaryDTO(String id, String name, Instant createdAt) { }
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
    public Class<Product> getEntityType() {
        return Product.class;
    }

    @Override
    public @Nullable ProductDetailedDTO map(final @Nullable Product product) {
        if (product == null) return null;
        return new ProductDetailedDTO(
                product.getId(),
                product.getName(),
                product.getDescription(),
                product.getCreatedAt(),
                product.getUpdatedAt(),
                product.getOwner());
    }
}
```

**FullLayoutStrategy** — all fields + expensive computations; **restricted** (it exposes permissions and history):
```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class ProductFullLayoutStrategy implements LayoutStrategy<Product, ProductFullDTO> {
    private final ProductMetadataService productMetadataService;
    private final ProductDetailsService productDetailsService;

    @Override
    public LayoutType getSupportedLayoutType() {
        return LayoutType.FULL;
    }

    @Override
    public Class<Product> getEntityType() {
        return Product.class;
    }

    @Override
    public boolean isRestricted() {
        return true;    // permissions and change history are not for every caller
    }

    @Override
    public @Nullable ProductFullDTO map(final @Nullable Product product) {
        if (product == null) return null;
        // Lazy associations are loaded inside the service's read-only transaction and returned as a read model;
        // touching product.getPermissions() / getChangeHistory() here would run outside it (LazyInitializationException).
        final ProductFullDetails details = productDetailsService.getFullDetails(product.getId());
        return new ProductFullDTO(
                product.getId(),
                product.getName(),
                product.getDescription(),
                product.getCreatedAt(),
                product.getUpdatedAt(),
                product.getOwner(),
                // Full layout includes expensive/computed fields
                productMetadataService.getMetadataFor(product.getId()),
                details.permissions(),
                details.changeHistory());
    }
}
```

**Rules for strategies:**
- A strategy never touches a lazy JPA association: the mapping runs after the service transaction has closed.
  Load what the layout needs inside the service (`@Transactional(readOnly = true)`, an `@EntityGraph` or a fetch join)
  and pass a read model, as `ProductFullDetails` above.
- On list endpoints, load the extra data for the whole page in one query — calling a per-item service from `map`
  is an N+1.
- `map` starts with `if (entity == null) return null;` and is declared `@Nullable D map(@Nullable E entity)` — the
  guard passes the NullAway gate (`static-analysis`); in practice the service throws `NotFoundException` first, so the
  handler never passes `null`.

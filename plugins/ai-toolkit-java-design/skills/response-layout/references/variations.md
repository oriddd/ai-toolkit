# Response Layout Skill — Variations

Part of the [`response-layout`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 7. Variations

### Layout + Permissions
Filter fields based on caller permissions. This **replaces** `ProductFullLayoutStrategy` — keep exactly
one strategy per (entity, layout); the registry fails at startup on a duplicate. Ask a boolean permission query
**first**, then build the immutable DTO once — never use a thrown 403 as control flow:
```java
@Component
@RequiredArgsConstructor
public class SecureFullLayoutStrategy implements LayoutStrategy<Product, ProductFullDTO> {
    private final ProductSensitiveDataPolicy sensitiveDataPolicy;   // port, implemented in permission/
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
        return true;    // still exposes permissions and history, like ProductFullLayoutStrategy
    }

    @Override
    public ProductFullDTO map(final Product product) {
        if (product == null) return null;
        final boolean mayReadSensitiveData = sensitiveDataPolicy.mayReadSensitiveData(product.getId());
        final ProductFullDetails details = productDetailsService.getFullDetails(product.getId());
        return new ProductFullDTO(
                product.getId(),
                product.getName(),
                product.getDescription(),
                product.getCreatedAt(),
                product.getUpdatedAt(),
                product.getOwner(),
                productMetadataService.getMetadataFor(product.getId()),
                details.permissions(),
                details.changeHistory(),
                mayReadSensitiveData ? details.sensitiveData() : null);   // omitted for other callers
    }
}
// ProductFullDTO gains a sensitiveData component (null → omitted with @JsonInclude(NON_NULL))

public interface ProductSensitiveDataPolicy {
    boolean mayReadSensitiveData(String productId);
}
```

### Layout from Accept Header
Use media type instead of query param. The response now varies by a request header, so add `Vary: Accept`
(`ResponseEntity.ok().varyBy(HttpHeaders.ACCEPT).body(dto)`), or shared caches serve one layout to every client:
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

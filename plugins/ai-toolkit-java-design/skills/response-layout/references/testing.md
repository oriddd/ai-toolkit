# Response Layout Skill — Testing

Part of the [`response-layout`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 8. Testing

Test each strategy in isolation (pure mapping, no Spring context) and the handler with a hand-built registry —
plain constructors, no mocks:
```java
private final LayoutHandler layoutHandler = new LayoutHandler(
        new LayoutResolver(),
        new LayoutRegistry(List.of(new ProductSummaryLayoutStrategy(), new ProductDetailedLayoutStrategy(), fullStrategy)),
        (layoutType, resourceId) -> allowRestricted);   // LayoutAccessPolicy

@Test
void map_nullEntity_returnsNull() {
    assertThat(new ProductSummaryLayoutStrategy().map(null)).isNull();
    assertThat(new ProductDetailedLayoutStrategy().map(null)).isNull();
    assertThat(fullStrategy.map(null)).isNull();
}

@Test
void map_product_returnsTheSummaryFields() {
    assertThat(new ProductSummaryLayoutStrategy().map(sampleProduct))
            .isEqualTo(new ProductSummaryDTO("p-1", "Widget", sampleProduct.getCreatedAt()));
}

@Test
void canHandle_onlyTheDeclaredLayout() {
    assertThat(new ProductSummaryLayoutStrategy().canHandle(LayoutType.SUMMARY)).isTrue();
    assertThat(new ProductSummaryLayoutStrategy().canHandle(LayoutType.FULL)).isFalse();
    assertThat(new ProductSummaryLayoutStrategy().canHandle(null)).isFalse();
}

@Test
void handle_noLayoutParam_returnsTheDetailedDto() throws Exception {
    final Object dto = layoutHandler.handle(Product.class, "p-1", sampleProduct, new MockHttpServletRequest());

    assertThat(dto).isInstanceOf(ProductDetailedDTO.class);
}

@Test
void handle_unknownLayout_isBadRequest() {
    final var request = new MockHttpServletRequest();
    request.setParameter("layout", "huge");

    assertThatThrownBy(() -> layoutHandler.handle(Product.class, "p-1", sampleProduct, request))
            .isInstanceOf(BadRequestException.class);
}

@Test
void handle_restrictedLayoutWithoutAccess_isForbidden() {
    allowRestricted = false;
    final var request = new MockHttpServletRequest();
    request.setParameter("layout", "full");

    assertThatThrownBy(() -> layoutHandler.handle(Product.class, "p-1", sampleProduct, request))
            .isInstanceOf(ForbiddenException.class);
}

@Test
void registry_noStrategyForTheEntity_returnsNull() {
    assertThat(new LayoutRegistry(List.of(new ProductSummaryLayoutStrategy())).find(Order.class, LayoutType.SUMMARY)).isNull();
}

@Test
void registry_twoStrategiesForSameEntityAndLayout_failsAtStartup() {
    assertThatThrownBy(() -> new LayoutRegistry(
            List.of(new ProductSummaryLayoutStrategy(), new ProductSummaryLayoutStrategy())))
            .isInstanceOf(IllegalStateException.class);
}
```

See strategy-registry-pattern and unit-tests for the full testing contract.

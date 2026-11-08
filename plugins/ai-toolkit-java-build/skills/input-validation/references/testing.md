# Input Validation Skill — Testing validators

Part of the [`input-validation`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 5. Testing

### 5a. Unit-testing rule beans

Rule beans have no Jakarta/Spring MVC dependency — test them as plain POJOs:

```java
class ProductEditabilityRuleTest {

    private final CatalogConfigService configService = mock(CatalogConfigService.class);
    private final ProductEditabilityRule rule = new ProductEditabilityRule(configService);

    @Test
    void isEditable_configSaysEditable_returnsTrue() {
        when(configService.getProductConfig("TypeA"))
            .thenReturn(configDto(true));
        assertThat(rule.isEditable("TypeA")).isTrue();
    }

    @Test
    void isEditable_configMissing_returnsFalse() {
        when(configService.getProductConfig("TypeA")).thenReturn(null);
        assertThat(rule.isEditable("TypeA")).isFalse();
    }
}
```

### 5b. Unit-testing the ConstraintValidator

Drive the validator directly, without Spring context:

```java
class EditableProductIdValidatorTest {
    private final ProductLookupService lookup = mock(ProductLookupService.class);
    private final ProductEditabilityRule rule  = mock(ProductEditabilityRule.class);
    private final ConstraintValidatorContext ctx = mock(ConstraintValidatorContext.class);
    private final HibernateConstraintValidatorContext hibernateCtx = mock(HibernateConstraintValidatorContext.class);
    private final ConstraintViolationBuilder builder = mock(ConstraintViolationBuilder.class);

    private final EditableProductIdValidator validator =
            new EditableProductIdValidator(lookup, rule);

    @BeforeEach void setUp() {
        when(ctx.buildConstraintViolationWithTemplate(any())).thenReturn(builder);
        when(builder.addConstraintViolation()).thenReturn(ctx);
        when(ctx.unwrap(HibernateConstraintValidatorContext.class)).thenReturn(hibernateCtx);
    }

    @Test
    void isValid_blankId_returnsFalse() {
        assertThat(validator.isValid("", ctx)).isFalse();
        verify(ctx).disableDefaultConstraintViolation();
    }

    @Test
    void isValid_productTypeNotEditable_returnsFalseWithProductIdParameter() {
        when(lookup.getProductType("id1")).thenReturn("TypeA");
        when(rule.isEditable("TypeA")).thenReturn(false);
        assertThat(validator.isValid("id1", ctx)).isFalse();
        verify(hibernateCtx).addMessageParameter("productId", "id1");
    }

    @Test
    void isValid_unknownProduct_returnsFalseLikeNotEditable() {   // same answer: no existence leak
        when(lookup.getProductType("id1")).thenReturn(null);
        assertThat(validator.isValid("id1", ctx)).isFalse();
        verify(hibernateCtx).addMessageParameter("productId", "id1");
    }

    @Test
    void isValid_productTypeEditable_returnsTrue() {
        when(lookup.getProductType("id1")).thenReturn("TypeA");
        when(rule.isEditable("TypeA")).thenReturn(true);
        assertThat(validator.isValid("id1", ctx)).isTrue();
        verifyNoInteractions(ctx);
    }
}
```

### 5c. Component test — end-to-end validation

Use a `@WebMvcTest` slice with `@MockitoBean` (Spring Boot 3.4+; replaces the deprecated `@MockBean`) on the
beans the slice does not load — the rule beans, the lookup services the validators use, and the controller's
own service/operation; fire a request whose body is otherwise **valid** and assert the 400 ProblemDetail and the
violation text (see `component-tests`):

```java
@WebMvcTest(ProductController.class)
class ProductControllerValidationTest {
    @Autowired MockMvc mockMvc;
    @MockitoBean ProductEditabilityRule editabilityRule;     // rule bean used by the validator
    @MockitoBean ProductLookupService productLookupService;  // lookup used by the validator
    @MockitoBean UpdateProductOperation updateProductOperation;  // the controller's own collaborator

    @Test
    void update_uneditableProductType_returns400WithViolation() throws Exception {
        when(productLookupService.getProductType("prod-1")).thenReturn("TypeA");
        when(editabilityRule.isEditable("TypeA")).thenReturn(false);
        mockMvc.perform(patch("/api/v1/products/prod-1")
                       .contentType(APPLICATION_JSON)
                       .content("{\"name\":\"New name\"}"))           // valid body: only the path rule fails
               .andExpect(status().isBadRequest())
               .andExpect(jsonPath("$.status").value(400))
               .andExpect(content().string(containsString("Product 'prod-1' is not editable")));
        verifyNoInteractions(updateProductOperation);
    }
}
```

- Mock **only** rule beans and downstream services. Validators themselves are
  not beans to mock: `ConstraintValidator`s are created by the validator factory,
  and a Spring `Validator` registered via `@InitBinder` must stay real — a
  Mockito mock's `supports()` returns `false`, so `addValidators` throws and the
  request ends in a 500.
- For full-context component tests, the same rule-bean doubles may live in the
  shared `ComponentTestConfiguration` instead of inline `@MockitoBean`s (see
  `component-tests`); pick one place per test class, never both.

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
    void whenConfigSaysEditable_returnsTrue() {
        when(configService.getProductConfig("TypeA"))
            .thenReturn(configDto(true));
        assertThat(rule.isEditable("TypeA")).isTrue();
    }

    @Test
    void whenConfigMissing_returnsFalse() {
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
    private final ConstraintViolationBuilder builder = mock(ConstraintViolationBuilder.class);

    private final EditableProductIdValidator validator =
            new EditableProductIdValidator(lookup, rule);

    @BeforeEach void setUp() {
        validator.initialize(annotation("Product '%s' of type '%s' is not editable"));
        when(ctx.buildConstraintViolationWithTemplate(any())).thenReturn(builder);
        when(builder.addConstraintViolation()).thenReturn(ctx);
    }

    @Test
    void blankId_isInvalid() {
        assertThat(validator.isValid("", ctx)).isFalse();
    }

    @Test
    void productTypeNotEditable_isInvalid() {
        when(lookup.getProductType("id1")).thenReturn("TypeA");
        when(rule.isEditable("TypeA")).thenReturn(false);
        assertThat(validator.isValid("id1", ctx)).isFalse();
        verify(ctx).disableDefaultConstraintViolation();
    }

    @Test
    void productTypeEditable_isValid() {
        when(lookup.getProductType("id1")).thenReturn("TypeA");
        when(rule.isEditable("TypeA")).thenReturn(true);
        assertThat(validator.isValid("id1", ctx)).isTrue();
        verifyNoInteractions(ctx);
    }
}
```

### 5c. Component test — end-to-end validation

Use a `@WebMvcTest` slice with `@MockitoBean` (Spring Boot 3.4+; replaces the deprecated `@MockBean`) on any rule beans; fire the request
and assert the 400 ProblemDetail response (see `component-tests`):

```java
@WebMvcTest(ProductController.class)
class ProductControllerValidationTest {
    @Autowired MockMvc mockMvc;
    @MockitoBean ProductEditabilityRule editabilityRule;  // MockitoBean so context loads

    @Test
    void patch_withUneditableProductType_returns400() throws Exception {
        when(editabilityRule.isEditable(any())).thenReturn(false);
        mockMvc.perform(patch("/api/v1/products/prod-1").contentType(APPLICATION_JSON).content("{}"))
               .andExpect(status().isBadRequest())
               .andExpect(jsonPath("$.status").value(400));
    }
}
```

- Add `@MockitoBean` in the component test for **every** Spring `@Component` that
  is a `ConstraintValidator` or `Validator` and is registered in
  `ValidationConfig` — Spring will fail to load the context otherwise.
- For Spring Validators registered via `@InitBinder`, `@MockitoBean` the validator
  class itself (not the rule bean) to avoid it executing real logic in the
  web-layer test.

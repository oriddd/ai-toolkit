---
name: validation-pattern
description: >
  Java / Spring Boot: background and rationale for input validation — why rules live in annotations, validators and
  rule beans, message design and testing strategy. Use when deciding how to externalize validation from business code;
  to write a validator apply `input-validation`.
tier: foundational
applies_to: [rest, monolith]
depends_on: [code-structure, spring-boot-conventions]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-07-12
---

# Validation Pattern (Foundational)

This is the **foundational pattern** for implementing declarative input validation in Spring Boot microservices. It achieves **separation of concerns** by moving validation logic out of controllers, operations, and services into dedicated, reusable, testable components.

> **Anti-pattern**: Ad-hoc `if (x == null) throw new BadRequestException(...)` blocks scattered throughout business logic. The validation layer owns input contracts; business logic assumes inputs are already valid.

## Pattern Overview

The pattern separates validation into distinct layers:

```
validation/
├── annotation/                       # Custom Jakarta @Constraint annotations
│   └── <CustomConstraint>.java
├── validator/                        # Validator implementations
│   ├── <FieldValidator>.java         # Jakarta ConstraintValidator (field/param level)
│   └── <ObjectValidator>.java        # Spring Validator (object/cross-field level)
├── rule/                             # Domain rule beans (pure logic, no validation framework)
│   └── <DomainRule>.java            # (or policy/, domain/, acl/ — named contextually)
└── config/
    └── ValidationConfig.java         # @ControllerAdvice for Spring Validator registration
```

## Two Validation Styles

| Style | When to Use | Applied At | Framework |
|-------|-------------|------------|-----------|
| **Jakarta ConstraintValidator** | Single field/parameter rule; reusable across endpoints; needs Spring beans | `@PathVariable`, `@RequestParam`, `@RequestBody` field, method parameter | Jakarta Bean Validation (JSR-380) |
| **Spring Validator** | Cross-field / object-level rule; depends on combination of fields | Full `@RequestBody` object via `@InitBinder` | Spring `org.springframework.validation.Validator` |

Both wire into Spring MVC's validation pipeline → HTTP 400 via `@RestControllerAdvice`.

## Component Responsibilities

### 1. **Annotations** — The Contract
- Interface with `@Constraint(validatedBy = {...})`
- Three mandatory elements: `message()`, `groups()`, `payload()`
- Optional custom attributes for parameterization
- Noun phrase names (`@EditableProductId`, `@ValidEmail`)

### 2. **Jakarta ConstraintValidator** — Field/Parameter Validation
- Implements `ConstraintValidator<Annotation, Type>`
- Is **not** a `@Component`: Spring's `SpringConstraintValidatorFactory` creates it through the context, so
  constructor injection works; one instance is cached per constraint and shared across threads
- Captures annotation attributes in `initialize()`
- Returns `true` (valid) or `false` + violation (invalid)
- Delegates domain logic to `rule/` beans
- Uses `rejectWith()` helper for custom messages

**Key Pattern:**
```java
@RequiredArgsConstructor
public class EditableProductIdValidator 
        implements ConstraintValidator<EditableProductId, String> {
    private final ProductEditabilityRule rule;  // domain logic bean

    @Override
    public void initialize(final EditableProductId annotation) {
        // capture annotation attributes here
    }

    @Override
    public boolean isValid(final String value, final ConstraintValidatorContext ctx) {
        if (value == null || value.isBlank()) {
            return rejectWith(ctx, "Product ID must not be blank");
        }
        return rule.isEditableProduct(value);
    }

    private boolean rejectWith(final ConstraintValidatorContext ctx, final String msg) {
        ctx.disableDefaultConstraintViolation();
        ctx.buildConstraintViolationWithTemplate(msg).addConstraintViolation();
        return false;
    }
}
```

**Apply in controller:**
```java
@RestController
@Validated  // REQUIRED — Boot < 3.2 silently ignores param constraints without it; 3.2+ it selects the ConstraintViolationException path
public class ProductController {
    @PatchMapping("/{id}")
    public ResponseEntity<ProductResponse> update(
            @PathVariable @EditableProductId String id,  // validated here
            @RequestBody @Valid UpdateProductRequest req) { ... }
}
```

### 3. **Spring Validator** — Object/Cross-Field Validation
- Implements `org.springframework.validation.Validator`
- Is a `@Component`
- `supports(Class)` returns true only for exact DTO
- `validate(Object, Errors)` performs logic
- Uses `errors.rejectValue()` for field violations
- Registered via `@InitBinder` in `ValidationConfig`

**Key Pattern:**
```java
@Component
public class CreateScheduleRequestValidator implements Validator {
    @Override
    public boolean supports(Class<?> clazz) {
        return CreateScheduleRequest.class.equals(clazz);
    }

    @Override
    public void validate(Object target, Errors errors) {
        final CreateScheduleRequest request = (CreateScheduleRequest) target;
        if (ScheduleType.RECURRING.equals(request.getType()) && request.getIntervalDays() == null) {
            errors.rejectValue("intervalDays", "schedule.recurring.intervalDays",
                    "intervalDays is required for RECURRING schedules");
        }
    }
}
```

**Register in ValidationConfig:**
```java
@ControllerAdvice
@RequiredArgsConstructor
public class ValidationConfig {
    private final CreateScheduleRequestValidator validator;

    @InitBinder("createScheduleRequest")  // lower-camel DTO name
    public void bind(WebDataBinder binder) {
        binder.addValidators(validator);
    }
}
```

### 4. **Domain Rule Beans** — Pure Business Logic
- Pure `@Component` with **no Jakarta or Spring MVC imports**
- Reusable across validators
- Unit-testable as POJOs
- Can call external services (via injected clients)
- Speaks domain language (`isEditable`, `isValidType`)

**Key Pattern:**
```java
@Component
@RequiredArgsConstructor
public class ProductEditabilityRule {
    private final ConfigService configService;

    public boolean isEditable(final String productType) {
        final Config config = configService.getConfig(productType);
        return config != null && config.isEditable();
    }

    public boolean isEditableProduct(final String productId) {
        final String productType = configService.getProductType(productId);
        return productType != null && isEditable(productType);
    }
}
```

## When to Use Each Style

**Jakarta ConstraintValidator:**
- ✅ Single field/parameter validation
- ✅ Reusable across endpoints
- ✅ Needs Spring beans (lookups, external calls)
- Examples: email format, product existence, custom business rules

**Spring Validator:**
- ✅ Cross-field validation
- ✅ DTO-specific rules
- ✅ Field relationships
- Examples: "startDate < endDate", "if type=X then field Y required"

## Testing

**Test Rule Beans** (POJOs):
```java
class ProductEditabilityRuleTest {
    @Test
    void isEditable_configSaysEditable_returnsTrue() {
        // mock configService, test rule.isEditable()
    }
}
```

**Test Jakarta Validator** (mock context):
```java
class EditableProductIdValidatorTest {
    private final ProductEditabilityRule rule = mock(ProductEditabilityRule.class);
    private final ConstraintValidatorContext ctx = mock(ConstraintValidatorContext.class);
    private final ConstraintViolationBuilder builder = mock(ConstraintViolationBuilder.class);
    private final EditableProductIdValidator validator = new EditableProductIdValidator(rule);

    @Test
    void isValid_blankId_returnsFalse() {
        when(ctx.buildConstraintViolationWithTemplate(any())).thenReturn(builder);   // stub, or rejectWith NPEs
        assertThat(validator.isValid(" ", ctx)).isFalse();
        verify(ctx).disableDefaultConstraintViolation();
    }
}
```

**Test Spring Validator** (drive validate):
```java
class CreateScheduleRequestValidatorTest {
    private final CreateScheduleRequestValidator validator = new CreateScheduleRequestValidator();

    @Test
    void validate_recurringWithoutInterval_rejectsIntervalDays() {
        var request = new CreateScheduleRequest(ScheduleType.RECURRING, null);
        var errors = new BeanPropertyBindingResult(request, "createScheduleRequest");
        validator.validate(request, errors);
        assertThat(errors.hasFieldErrors("intervalDays")).isTrue();
    }
}
```

**Component Test** (HTTP → 400):
```java
@WebMvcTest(ProductController.class)
class ProductControllerValidationTest {
    @Autowired MockMvc mockMvc;
    @MockitoBean ProductEditabilityRule rule;   // Spring Boot 3.4+; replaces the deprecated @MockBean
    @MockitoBean UpdateProductOperation operation;   // the controller's own collaborator

    @Test
    void update_uneditableProduct_returns400() throws Exception {
        when(rule.isEditableProduct("p-1")).thenReturn(false);
        mockMvc.perform(patch("/api/v1/products/p-1")
                .contentType(MediaType.APPLICATION_JSON)        // without it: 415, not the 400 under test
                .content("{\"name\":\"New name\"}"))            // otherwise valid body
            .andExpect(status().isBadRequest());
    }
}
```

## Do / Don't

✅ **Do:**
- Put domain logic in `rule/` beans — validators orchestrate only
- Use Jakarta for field/param; Spring for cross-field
- Add `@Validated` on controller for parameter validation
- Bind Spring Validators with scoped `@InitBinder("dtoName")`
- Test each layer independently

❌ **Don't:**
- Write `if/throw` in controllers/operations — use validators
- Put business logic in validators — use `rule/` beans
- Omit `@InitBinder` value — runs on every request
- Skip `@MockitoBean` for the rule beans / downstream services a web-slice test needs — but never mock a
  registered Spring `Validator` itself (its mock `supports()` returns false → 500)

## Implementation Checklist

- [ ] Decide: Jakarta (field/param) or Spring (cross-field)?
- [ ] Create domain rule bean in `rule/`
- [ ] Unit-test rule bean
- [ ] For Jakarta: Create annotation + validator
- [ ] For Spring: Create validator + register in ValidationConfig
- [ ] Add `@Validated` or `@Valid` to controller
- [ ] Unit-test validator
- [ ] Component-test HTTP→400 path
- [ ] Add `@MockitoBean` for the rule beans / downstream services in affected tests (never for a registered `Validator`)

## Related Skills

This pattern is applied in:
- **input-validation** — Full implementation guide with detailed examples
- **exception-handling** — Maps validation exceptions to HTTP 400
- **code-structure** — Defines `validation/` package placement

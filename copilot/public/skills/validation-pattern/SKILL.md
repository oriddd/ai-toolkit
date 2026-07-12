---
name: validation-pattern
description: Foundational pattern for implementing input validation in Spring Boot microservices using Jakarta Bean Validation (ConstraintValidator) for field/parameter-level rules and Spring Validator for object/cross-field rules. Covers the separation of concerns (annotations, validators, domain rule beans), custom constraint authoring, annotation attribute propagation, constraint violation messaging, and testing strategies. Apply whenever validation logic needs to be externalized from business code.
tier: foundational
applies_to: [rest, event, monolith]
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
│   └── <DomainRule>.java            # (or ddm/, domain/, acl/ — named contextually)
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
- Noun phrase names (`@EditableEntityId`, `@ValidEmail`)

### 2. **Jakarta ConstraintValidator** — Field/Parameter Validation
- Implements `ConstraintValidator<Annotation, Type>`
- Is a `@Component` (Spring auto-wires dependencies)
- Captures annotation attributes in `initialize()`
- Returns `true` (valid) or `false` + violation (invalid)
- Delegates domain logic to `rule/` beans
- Uses `rejectWith()` helper for custom messages

**Key Pattern:**
```java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class EditableEntityIdValidator 
        implements ConstraintValidator<EditableEntityId, String> {
    private final EntityEditabilityRule rule;  // domain logic bean
    private String messageTemplate;

    @Override
    public void initialize(final EditableEntityId annotation) {
        this.messageTemplate = annotation.message();
    }

    @Override
    public boolean isValid(final String value, final ConstraintValidatorContext ctx) {
        if (invalid) {
            return rejectWith(ctx, "Custom error message");
        }
        return rule.checkDomainLogic(value);
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
@Validated  // REQUIRED for parameter validation
public class EntityController {
    @PatchMapping("/{id}")
    public ResponseEntity update(
            @PathVariable @EditableEntityId String id,  // validated here
            @RequestBody @Valid Request req) { ... }
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
public class CreateScheduleValidator implements Validator {
    @Override
    public boolean supports(Class<?> clazz) {
        return CreateScheduleRequest.class.equals(clazz);
    }

    @Override
    public void validate(Object target, Errors errors) {
        final CreateScheduleRequest req = (CreateScheduleRequest) target;
        if (req.getType() == RECURRING && req.getInterval() == null) {
            errors.rejectValue("interval", "code", "interval required for RECURRING");
        }
    }
}
```

**Register in ValidationConfig:**
```java
@ControllerAdvice
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class ValidationConfig {
    private final CreateScheduleValidator validator;

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
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class EntityEditabilityRule {
    private final ConfigService configService;

    public boolean isEditable(final String entityType) {
        final Config config = configService.getConfig(entityType);
        return config != null && config.isEditable();
    }
}
```

## When to Use Each Style

**Jakarta ConstraintValidator:**
- ✅ Single field/parameter validation
- ✅ Reusable across endpoints
- ✅ Needs Spring beans (lookups, external calls)
- Examples: email format, entity existence, custom business rules

**Spring Validator:**
- ✅ Cross-field validation
- ✅ DTO-specific rules
- ✅ Field relationships
- Examples: "startDate < endDate", "if type=X then field Y required"

## Testing

**Test Rule Beans** (POJOs):
```java
class EntityEditabilityRuleTest {
    @Test
    void whenEditable_returnsTrue() {
        // mock configService, test rule.isEditable()
    }
}
```

**Test Jakarta Validator** (mock context):
```java
class ValidatorTest {
    @Test
    void whenInvalid_returnsFalse() {
        assertThat(validator.isValid(badValue, ctx)).isFalse();
        verify(ctx).disableDefaultConstraintViolation();
    }
}
```

**Test Spring Validator** (drive validate):
```java
class ValidatorTest {
    @Test
    void whenMissingField_rejectsValue() {
        validator.validate(request, errors);
        assertThat(errors.hasFieldErrors("field")).isTrue();
    }
}
```

**Component Test** (HTTP → 400):
```java
@WebMvcTest(Controller.class)
class ValidationComponentTest {
    @MockBean EntityEditabilityRule rule;

    @Test
    void invalidRequest_returns400() {
        mockMvc.perform(post("/api").content("{}"))
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
- Skip `@MockBean` in component tests

## Implementation Checklist

- [ ] Decide: Jakarta (field/param) or Spring (cross-field)?
- [ ] Create domain rule bean in `rule/`
- [ ] Unit-test rule bean
- [ ] For Jakarta: Create annotation + validator
- [ ] For Spring: Create validator + register in ValidationConfig
- [ ] Add `@Validated` or `@Valid` to controller
- [ ] Unit-test validator
- [ ] Component-test HTTP→400 path
- [ ] Add `@MockBean` for affected tests

## Related Skills

This pattern is applied in:
- **input-validation** — Full implementation guide with detailed examples
- **exception-handling** — Maps validation exceptions to HTTP 400
- **code-structure** — Defines `validation/` package placement

---

**Version:** 1.0  
**Last Reviewed:** 2026-07-12

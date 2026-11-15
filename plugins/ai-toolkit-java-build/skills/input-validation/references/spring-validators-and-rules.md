# Input Validation Skill — Style B — Spring Validator and domain rule beans

Part of the [`input-validation`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 3. Style B — Spring `Validator` (object / cross-field level)

Use `org.springframework.validation.Validator` when the rule spans multiple
fields in the same DTO (e.g. "if `type == RECURRING` then `intervalDays` must
be set").

### 3a. The validator class

```java
// validator/CreateScheduleRequestValidator.java
@Component
@RequiredArgsConstructor
public class CreateScheduleRequestValidator implements Validator {

    @Override
    public boolean supports(@NonNull final Class<?> clazz) {
        return CreateScheduleRequest.class.equals(clazz);
    }

    @Override
    public void validate(@NonNull final Object target,
                         @NonNull final Errors errors) {
        final CreateScheduleRequest request = (CreateScheduleRequest) target;

        if (ScheduleType.RECURRING.equals(request.type())          // DTOs are records: accessor type(), not getType()
                && request.intervalDays() == null) {
            errors.rejectValue(
                    "intervalDays",                        // field path
                    "schedule.recurring.intervalDays",     // error code
                    "intervalDays is required for RECURRING schedules");
        }
    }
}
```

Rules:
- `supports()` returns `true` only for the exact DTO class. If accidentally
  bound to the wrong type, the cast in `validate()` will throw.
- Use `errors.rejectValue(fieldPath, errorCode, message)` for field-level
  violations and `errors.reject(errorCode, message)` for object-level ones.
- Error codes follow the convention `<product>.<field>.<reason>`
  (e.g. `schedule.recurring.intervalDays`).
- Keep one rule per `if` block; extract helpers if the validator grows beyond
  ~30 LOC.

### 3b. Registering in `ValidationConfig`

```java
// config/ValidationConfig.java
@ControllerAdvice
@RequiredArgsConstructor
public class ValidationConfig {

    private final CreateScheduleRequestValidator createScheduleRequestValidator;

    /**
     * Binds CreateScheduleRequestValidator to CreateScheduleRequest bodies.
     * The string "createScheduleRequest" is the lower-camel-case DTO class name,
     * which tells Spring to bind ONLY when the body type matches — preventing
     * the validator from running on every request.
     */
    @InitBinder("createScheduleRequest")
    public void bindCreateScheduleValidator(final WebDataBinder binder) {
        binder.addValidators(createScheduleRequestValidator);
    }
}
```

Rules:
- The `@InitBinder` value **must** be the lower-camel-case name of the DTO
  class (e.g. `"createScheduleRequest"` for `CreateScheduleRequest.class`).
  Omitting it binds the validator to **every** request — almost always wrong.
- One `@InitBinder` method per registered validator.
- Add `@Valid` on the matching `@RequestBody` parameter in the controller;
  without it Spring's binding phase does not call the validators.

## 4. Domain rule beans (`rule/`)

Validators must be thin orchestrators — they detect a violation and format the
message, but they do not own domain logic. Extract all domain logic into
dedicated `@Component` beans in `rule/`:

```java
// rule/ProductEditabilityRule.java  (or policy/ProductTypeValidator.java)
@Component
@RequiredArgsConstructor
@Slf4j
public class ProductEditabilityRule {
    private final CatalogConfigService catalogConfigService;   // injected external client

    public boolean isEditable(final String productType) {
        final CatalogProductConfigDto config = catalogConfigService.getProductConfig(productType);
        if (config == null) {
            log.warn("Domain configuration missing for product type: {}", productType);
            return false;
        }
        return Boolean.TRUE.equals(config.isEditable());
    }

    public boolean isExistent(final String productType) {
        return catalogConfigService.getProductConfig(productType) != null;
    }
    
    public boolean isCreatableByUser(final String productType) {
        final CatalogProductConfigDto config = catalogConfigService.getProductConfig(productType);
        return config != null && Boolean.TRUE.equals(config.isCreatable());
    }
}
```

**Note on package naming:** The `rule/` package can be named contextually based on 
your domain (e.g., `policy/` for policy rules, `domain/` for domain rules, 
`acl/` for access-control rules). The key is that it contains **pure domain logic** 
with no Jakarta or Spring MVC imports.

Benefits:
- Rule beans are **unit-testable in isolation** — no Jakarta machinery needed.
- The same rule can be reused by multiple validators without duplication.
- When the rule's underlying technology changes (different config service) only
  the rule bean changes, not the validator.

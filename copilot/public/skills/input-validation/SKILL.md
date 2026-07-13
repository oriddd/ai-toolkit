---
name: input-validation
description: Implement all input validation in a Spring Boot microservice using Jakarta Bean Validation (ConstraintValidator) for field/parameter-level rules and Spring Validator (org.springframework.validation.Validator) for object/cross-field rules. Covers custom annotation authoring, Spring-bean-aware validators with injected domain rule beans, annotation attribute propagation via initialize(), custom constraint violation messages, ValidationConfig @ControllerAdvice registration via @InitBinder, and the canonical package layout. Use whenever a new validation rule is required — never write ad-hoc if/throw guards in controllers, operations, or services when a validator can own the contract.
tier: must
applies_to: [rest, monolith]
depends_on: [code-structure, exception-handling, spring-boot-conventions, validation-pattern]
ships_templates: false
hitl: true
version: 1.3
last_reviewed: 2026-07-13
---

# Input Validation Skill (public)

> **Pattern Foundation:** This skill is a concrete application of the [validation-pattern](../validation-pattern/SKILL.md) skill. 
> Read that skill first to understand the foundational pattern, then return here for detailed implementation examples and edge cases.

Validation is a **first-class concern** in every Spring Boot service. This skill
defines the two canonical validation styles, when to use each, the package
layout, and the full authoring contract for both. Validation errors surface as
RFC 7807 `ProblemDetail` 400 responses — wired automatically by the
`@RestControllerAdvice` from the `exception-handling` skill.

> Ad-hoc `if (x == null) throw new BadRequestException(...)` blocks inside
> controllers, operations, or services are an **anti-pattern**. The validation
> layer owns input contracts; business logic assumes inputs are already valid.

## 0. CRITICAL: Check OpenAPI Schema First (Avoid Redundancy)

**STOP: Before creating custom validators, check if OpenAPI already handles it:**

### OpenAPI Handles These Validations (DON'T Create Custom Validators)

| Validation Type | OpenAPI Syntax | Example |
|-----------------|----------------|---------|
| **Enum values** | `enum: [value1, value2]` | `layout: enum: [all, metadata]` |
| **Format** | `format: email/uri/date` | `email: {type: string, format: email}` |
| **Range** | `minimum/maximum` | `age: {type: integer, minimum: 0, maximum: 150}` |
| **Length** | `minLength/maxLength` | `name: {type: string, minLength: 1, maxLength: 100}` |
| **Pattern** | `pattern: "regex"` | `phone: {type: string, pattern: "^\\+[0-9]+$"}` |
| **Required** | `required: [field]` | `required: [userId, action]` |
| **Array size** | `minItems/maxItems` | `tags: {type: array, minItems: 1}` |

**If OpenAPI can express it → DON'T create custom validator (redundant!)**

### Custom Validators ONLY For These

| Validation Type | Why Custom Needed | Example |
|-----------------|-------------------|---------|
| **Cross-field** | Multiple fields interact | `startDate < endDate` |
| **Business rules** | Domain logic | `age >= 18 for accountType=PREMIUM` |
| **Database lookups** | External state | `userId exists in DB` |
| **Complex logic** | Beyond simple regex | `IBAN checksum validation` |
| **Conditional** | Rule depends on another field | `If country=US, state required` |

### Decision Tree

```
Does validation involve:
├─ Single field, simple check (enum, range, format, pattern)?
│  └─ Can OpenAPI express it?
│     ├─ YES → Use OpenAPI schema ← NO custom validator
│     └─ NO → Custom Jakarta ConstraintValidator
└─ Multiple fields or complex business logic?
   └─ Custom Spring Validator (cross-field)
```

### Anti-Pattern Example

```yaml
# api.yaml
parameters:
  - name: layout
    schema:
      type: string
      enum: [all, metadata]  # ← OpenAPI already validates!
```

```java
// ❌ REDUNDANT - OpenAPI Generator already validates enum
@Target({ElementType.PARAMETER, ElementType.FIELD})
@Constraint(validatedBy = WorkflowLayoutValidator.class)
public @interface ValidWorkflowLayout { ... }

@Component
public class WorkflowLayoutValidator implements ConstraintValidator<ValidWorkflowLayout, String> {
    public boolean isValid(String value, ConstraintValidatorContext context) {
        return value.equals("all") || value.equals("metadata");  // ← Duplicates OpenAPI
    }
}
```

**Fix**: Delete custom validator, OpenAPI handles it.

---

## Two canonical styles

| Style | When to use | Applied at |
| --- | --- | --- |
| **Jakarta `ConstraintValidator`** | Single field / parameter rule; rule reusable across endpoints; rule needs Spring beans (e.g. a domain lookup service) | `@PathVariable`, `@RequestParam`, `@RequestBody` field, method parameter, record component |
| **Spring `Validator`** | Cross-field / object-level rule; rule depends on the combination of multiple fields in the same DTO | Full `@RequestBody` object, bound via `@InitBinder` in `ValidationConfig` |

Both styles wire seamlessly into Spring MVC's validation pipeline and are
mapped to 400 by the `@RestControllerAdvice` (see `exception-handling`):
- Jakarta violations → `ConstraintViolationException` or
  `MethodArgumentNotValidException` → 400 `ProblemDetail`.
- Spring `Errors` rejections → `BindException` → 400 `ProblemDetail`.

## 1. Package layout

```
validation/
├── annotation/      # custom Jakarta @Constraint annotations only
├── validator/       # ConstraintValidator + Spring Validator implementations
├── rule/            # reusable domain rule beans (no Jakarta/Spring imports here)
│   └── (or ddm/, domain/, etc. — name contextually)
└── config/
    └── ValidationConfig.java    # @ControllerAdvice that registers Spring Validators
```

Rules:
- **`annotation/`** contains only annotation interfaces — no logic.
- **`validator/`** contains validator implementations that *delegate* logic to
  `rule/` beans. Validators know how to produce constraint violations; they do
  not own business rule logic themselves.
- **`rule/`** (or `ddm/`, `domain/`, etc.) contains pure Spring `@Component` beans 
  that express a single domain rule (`isEntityEditable`, `isRelationTypeDefined`, …). 
  These are injectable, unit-testable in isolation, and reusable across multiple
  validators. No Jakarta or Spring MVC imports allowed here — they speak the
  domain language only. **May call external services** (via injected clients) to
  fetch configuration or lookup data.
- **`config/`** holds `ValidationConfig` and nothing else.

## 2. Style A — Jakarta `ConstraintValidator` (field / parameter level)

### 2a. The annotation

Every custom constraint is an annotation interface with exactly three mandatory
elements (`message`, `groups`, `payload`) and declares its validator via
`@Constraint(validatedBy = {...})`.

```java
// annotation/EditableEntityId.java
@Constraint(validatedBy = {EditableEntityIdValidator.class})
@Target({ElementType.PARAMETER, ElementType.FIELD})
@Retention(RetentionPolicy.RUNTIME)
@Documented
public @interface EditableEntityId {
    String message() default "Entity with id '%s' is of type '%s' which is not editable";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}
```

Rules:
- **Always include `message`, `groups`, `payload`** — Jakarta requires them.
- Use a `%s`-style template in `message` when the violation text must include
  runtime values (entity id, type, …); the validator formats it dynamically
  (§2c).
- `@Target` must include `ElementType.PARAMETER` to apply to controller method
  parameters (the most common case) and optionally `ElementType.FIELD` for DTO
  fields.
- Keep the annotation name a **noun phrase** describing what it asserts (e.g.
  `@EditableEntityId`, `@ValidRelationType`) — not how it works.

### 2b. The validator class

The validator is a Spring `@Component` that implements
`ConstraintValidator<AnnotationType, ValueType>`. Spring's `LocalValidatorFactoryBean`
auto-discovers and injects Spring beans into `ConstraintValidator` implementations —
constructor injection works exactly as in any other Spring bean.

```java
// validator/EditableEntityIdValidator.java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
@Slf4j
public class EditableEntityIdValidator
        implements ConstraintValidator<EditableEntityId, String> {

    private final EntityLookupService entityLookupService;  // Spring bean from rule/
    private final EntityEditabilityRule entityEditabilityRule;  // domain rule bean

    private String messageTemplate;  // captured from annotation in initialize()

    @Override
    public void initialize(final EditableEntityId annotation) {
        this.messageTemplate = annotation.message();
        // Capture any other annotation attributes (targetType, relationType, …) here.
        // Example: this.targetType = annotation.targetType();
    }

    @Override
    public boolean isValid(final String entityId,
                           final ConstraintValidatorContext ctx) {
        if (StringUtils.isBlank(entityId)) {
            return rejectWith(ctx, "Entity ID must not be blank");
        }

        final String entityType = entityLookupService.getEntityType(entityId);
        if (StringUtils.isBlank(entityType)) {
            return rejectWith(ctx, String.format("Type for entity '%s' could not be determined", entityId));
        }

        if (entityEditabilityRule.isEditable(entityType)) {
            return true;
        }

        // Use the captured messageTemplate with runtime values
        return rejectWith(ctx, String.format(messageTemplate, entityId, entityType));
    }

    /**
     * Helper to build a constraint violation with a custom message.
     * Disables the default violation and adds the custom one.
     */
    private boolean rejectWith(final ConstraintValidatorContext ctx, final String message) {
        ctx.disableDefaultConstraintViolation();
        ctx.buildConstraintViolationWithTemplate(message).addConstraintViolation();
        return false;
    }
}
```

Rules:
- **`initialize()`** must capture every annotation attribute you need at
  validation time. The annotation instance passed here is the one from the
  annotated element — that is where `targetEntityType`, `relationType`, and
  other annotation parameters live.
- **`isValid()`** must return `false` + call `rejectWith(...)` when invalid, or
  return `true` when valid. Never throw inside `isValid()` — Jakarta catches
  exceptions and treats them as validation failures, masking the real error.
- Use `ctx.disableDefaultConstraintViolation()` + `buildConstraintViolationWithTemplate()`
  whenever you compute the message at runtime (runtime values in the template).
  Skip it only when the annotation's static `message` is sufficient.
- The private `rejectWith(ctx, message)` helper (or equivalent) eliminates the
  three-line violation-building boilerplate and keeps `isValid` readable.
- **Null/blank check is always the first guard** — by Jakarta convention,
  `null` is considered valid by built-in constraints; your custom validator
  should decide explicitly.

### 2c. Applying the annotation

On controller method parameters (`@PathVariable`, `@RequestParam`, or a
single-field `@RequestBody`):

```java
@RestController
@RequestMapping("/api/v1/entities")
@Validated  // REQUIRED on the controller — enables parameter-level validation
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class EntityController {

    @PatchMapping("/{entityId}")
    public ResponseEntity<EntityResponse> update(
            @PathVariable @EditableEntityId String entityId,
            @RequestBody @Valid UpdateEntityRequest request) {
        // entityId is already validated — no ad-hoc checks needed
        ...
    }
}
```

- `@Validated` on the controller class enables Spring's method-level validation
  proxying; without it, `@EditableEntityId` on a `@PathVariable` is silently
  ignored.
- `@Valid` on `@RequestBody` triggers nested Jakarta validation of DTO fields.
- Both `@Validated` (parameter constraints) and `@Valid` (nested DTO constraints)
  can be active on the same method.

### 2d. Annotation with extra attributes

When the same constraint is parameterized (e.g. "is this entity type valid for
relation type X with target entity type Y"):

```java
// annotation/ValidRelationType.java
@Constraint(validatedBy = {ValidRelationTypeValidator.class})
@Target(ElementType.PARAMETER)
@Retention(RetentionPolicy.RUNTIME)
@Documented
public @interface ValidRelationType {
    String targetEntityType();    // required annotation attribute
    String relationType();        // required annotation attribute

    String message() default "Entity '%s' of type '%s' cannot be in relation '%s' with entity type '%s'";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}
```

```java
// Usage on controller parameter:
public ResponseEntity<RelationResponse> createRelation(
        @PathVariable @ValidRelationType(
                targetEntityType = "ArtifactEntity",
                relationType     = "BELONGS_TO"
        ) String sourceEntityId) { ... }
```

The validator captures `targetEntityType` and `relationType` in `initialize()`
and uses them in `isValid()`.

## 3. Style B — Spring `Validator` (object / cross-field level)

Use `org.springframework.validation.Validator` when the rule spans multiple
fields in the same DTO (e.g. "if `type == RECURRING` then `intervalDays` must
be set").

### 3a. The validator class

```java
// validator/CreateScheduleRequestValidator.java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
public class CreateScheduleRequestValidator implements Validator {

    @Override
    public boolean supports(@NonNull final Class<?> clazz) {
        return CreateScheduleRequest.class.equals(clazz);
    }

    @Override
    public void validate(@NonNull final Object target,
                         @NonNull final Errors errors) {
        final CreateScheduleRequest request = (CreateScheduleRequest) target;

        if (ScheduleType.RECURRING.equals(request.getType())
                && request.getIntervalDays() == null) {
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
- Error codes follow the convention `<entity>.<field>.<reason>`
  (e.g. `schedule.recurring.intervalDays`).
- Keep one rule per `if` block; extract helpers if the validator grows beyond
  ~30 LOC.

### 3b. Registering in `ValidationConfig`

```java
// config/ValidationConfig.java
@ControllerAdvice
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
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
// rule/EntityEditabilityRule.java  (or ddm/EntityTypeValidator.java)
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
@Slf4j
public class EntityEditabilityRule {
    private final DomainConfigService domainConfigService;   // injected external client

    public boolean isEditable(final String entityType) {
        final DomainEntityConfigDto config = domainConfigService.getEntityConfig(entityType);
        if (config == null) {
            log.warn("Domain configuration missing for entity type: {}", entityType);
            return false;
        }
        return Boolean.TRUE.equals(config.isEditable());
    }

    public boolean isExistent(final String entityType) {
        return domainConfigService.getEntityConfig(entityType) != null;
    }
    
    public boolean isCreatableByUser(final String entityType) {
        final DomainEntityConfigDto config = domainConfigService.getEntityConfig(entityType);
        return config != null && Boolean.TRUE.equals(config.isCreatable());
    }
}
```

**Note on package naming:** The `rule/` package can be named contextually based on 
your domain (e.g., `ddm/` for data-model rules, `domain/` for domain rules, 
`acl/` for access-control rules). The key is that it contains **pure domain logic** 
with no Jakarta or Spring MVC imports.

Benefits:
- Rule beans are **unit-testable in isolation** — no Jakarta machinery needed.
- The same rule can be reused by multiple validators without duplication.
- When the rule's underlying technology changes (different config service) only
  the rule bean changes, not the validator.

## 5. Testing

### 5a. Unit-testing rule beans

Rule beans have no Jakarta/Spring MVC dependency — test them as plain POJOs:

```java
class EntityEditabilityRuleTest {

    private final DomainConfigService configService = mock(DomainConfigService.class);
    private final EntityEditabilityRule rule = new EntityEditabilityRule(configService);

    @Test
    void whenConfigSaysEditable_returnsTrue() {
        when(configService.getEntityConfig("TypeA"))
            .thenReturn(configDto(true));
        assertThat(rule.isEditable("TypeA")).isTrue();
    }

    @Test
    void whenConfigMissing_returnsFalse() {
        when(configService.getEntityConfig("TypeA")).thenReturn(null);
        assertThat(rule.isEditable("TypeA")).isFalse();
    }
}
```

### 5b. Unit-testing the ConstraintValidator

Drive the validator directly, without Spring context:

```java
class EditableEntityIdValidatorTest {
    private final EntityLookupService lookup = mock(EntityLookupService.class);
    private final EntityEditabilityRule rule  = mock(EntityEditabilityRule.class);
    private final ConstraintValidatorContext ctx = mock(ConstraintValidatorContext.class);
    private final ConstraintViolationBuilder builder = mock(ConstraintViolationBuilder.class);

    private final EditableEntityIdValidator validator =
            new EditableEntityIdValidator(lookup, rule);

    @BeforeEach void setUp() {
        validator.initialize(annotation("Entity '%s' of type '%s' is not editable"));
        when(ctx.buildConstraintViolationWithTemplate(any())).thenReturn(builder);
        when(builder.addConstraintViolation()).thenReturn(ctx);
    }

    @Test
    void blankId_isInvalid() {
        assertThat(validator.isValid("", ctx)).isFalse();
    }

    @Test
    void entityTypeNotEditable_isInvalid() {
        when(lookup.getEntityType("id1")).thenReturn("TypeA");
        when(rule.isEditable("TypeA")).thenReturn(false);
        assertThat(validator.isValid("id1", ctx)).isFalse();
        verify(ctx).disableDefaultConstraintViolation();
    }

    @Test
    void entityTypeEditable_isValid() {
        when(lookup.getEntityType("id1")).thenReturn("TypeA");
        when(rule.isEditable("TypeA")).thenReturn(true);
        assertThat(validator.isValid("id1", ctx)).isTrue();
        verifyNoInteractions(ctx);
    }
}
```

### 5c. Component test — end-to-end validation

Use a `@WebMvcTest` slice with `@MockBean` on any rule beans; fire the request
and assert the 400 ProblemDetail response (see `component-tests`):

```java
@WebMvcTest(EntityController.class)
class EntityControllerValidationTest {
    @Autowired MockMvc mockMvc;
    @MockBean  EntityEditabilityRule editabilityRule;  // MockBean so context loads

    @Test
    void patch_withUneditableEntityType_returns400() throws Exception {
        when(editabilityRule.isEditable(any())).thenReturn(false);
        mockMvc.perform(patch("/api/v1/entities/ent-1").contentType(APPLICATION_JSON).content("{}"))
               .andExpect(status().isBadRequest())
               .andExpect(jsonPath("$.status").value(400));
    }
}
```

- Add `@MockBean` in the component test for **every** Spring `@Component` that
  is a `ConstraintValidator` or `Validator` and is registered in
  `ValidationConfig` — Spring will fail to load the context otherwise.
- For Spring Validators registered via `@InitBinder`, `@MockBean` the validator
  class itself (not the rule bean) to avoid it executing real logic in the
  web-layer test.

## 6. Bootstrapping checklist

When adding a new validation rule:

- [ ] Decide: **parameter/field rule** (Jakarta `ConstraintValidator`) or
      **object/cross-field rule** (Spring `Validator`)?
- [ ] Create the domain rule bean in `rule/`, unit-test it in isolation.
- [ ] For **Jakarta style**: create the annotation in `annotation/`, the
      validator in `validator/`; add `@Validated` to the controller class.
- [ ] For **Spring style**: create the validator in `validator/`; add a bean
      field + `@InitBinder` method in `ValidationConfig`; add `@Valid` to
      the `@RequestBody` parameter.
- [ ] Map the violation to the right HTTP status in the
      `@RestControllerAdvice` if not already covered (see `exception-handling`).
- [ ] Unit-test the rule bean, unit-test the validator, add a component test
      asserting the 400 response.
- [ ] Add a `@MockBean` for the validator (Spring style) or for the rule bean
      (Jakarta style) in affected controller component tests.

## Do / Don't

✅ Put all domain logic in `rule/` beans — validators are thin orchestrators.
✅ Use Jakarta `@Constraint` for parameter/field rules; Spring `Validator` for
   cross-field / object-level rules.
✅ Always call `ctx.disableDefaultConstraintViolation()` before
   `buildConstraintViolationWithTemplate(message)` when overriding the message
   at runtime.
✅ Add `@Validated` to the controller class when using parameter-level Jakarta
   constraints — without it the annotation is silently ignored.
✅ Bind Spring Validators with a scoped `@InitBinder("lowerCamelDtoName")`
   value — omitting the value runs the validator on every request.
✅ Unit-test rule beans as plain POJOs; unit-test validators by driving
   `isValid()` directly; component-test the full HTTP→400 path.
❌ Never write `if (x == null) throw new BadRequestException(...)` in a
   controller, operation, or service — move the rule to the validation layer.
❌ Never perform database or remote calls directly inside a validator — use an
   injected `rule/` bean (easier to test, easier to cache).
❌ Never share a thread-unsafe field (mutable instance state other than values
   captured in `initialize()`) inside a `ConstraintValidator` — Spring
   validators are singletons.
❌ Never skip `@MockBean` for registered validators in controller component
   tests — the context will fail to load.

## Cross-references

- [`exception-handling`](../exception-handling/SKILL.md) — maps
  `ConstraintViolationException` and `MethodArgumentNotValidException` to 400
  `ProblemDetail`; must be set up for validation errors to appear correctly.
- [`spring-boot-conventions`](../spring-boot-conventions/SKILL.md) §4 — JSR-380
  `@Valid` / `@Validated` wiring on controllers.
- [`code-structure`](../code-structure/SKILL.md) — package layout and layering
  rules the `validation/` package plugs into.
- [`component-tests`](../component-tests/SKILL.md) — `@WebMvcTest` slice for
  end-to-end validation path testing.
- [`unit-tests`](../unit-tests/SKILL.md) — testing rule beans and validators in
  isolation.


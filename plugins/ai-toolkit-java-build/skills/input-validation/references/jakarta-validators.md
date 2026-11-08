# Input Validation Skill — Style A — Jakarta ConstraintValidator

Part of the [`input-validation`](../SKILL.md) skill. Section numbers and headings are stable; other skills cite them.

## 2. Style A — Jakarta `ConstraintValidator` (field / parameter level)

### 2a. The annotation

Every custom constraint is an annotation interface with exactly three mandatory
elements (`message`, `groups`, `payload`) and declares its validator via
`@Constraint(validatedBy = {...})`.

```java
// annotation/EditableProductId.java
@Constraint(validatedBy = {EditableProductIdValidator.class})
@Target({ElementType.PARAMETER, ElementType.FIELD})
@Retention(RetentionPolicy.RUNTIME)
@Documented
public @interface EditableProductId {
    String message() default "Product '{productId}' is not editable";   // {productId}: message parameter set by the validator
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}
```

Rules:
- **Always include `message`, `groups`, `payload`** — Jakarta requires them.
- When the violation text must include runtime values, put a **named
  parameter** (`{productId}`) in `message` and set it in the validator with
  `HibernateConstraintValidatorContext.addMessageParameter` (§2b). Never a
  `%s` placeholder: Bean Validation does not format it, so the default
  violation would show a literal `%s`.
- `@Target` must include `ElementType.PARAMETER` to apply to controller method
  parameters (the most common case) and optionally `ElementType.FIELD` for DTO
  fields.
- Keep the annotation name a **noun phrase** describing what it asserts (e.g.
  `@EditableProductId`, `@ValidShippingMethod`) — not how it works.

### 2b. The validator class

The validator implements `ConstraintValidator<AnnotationType, ValueType>`.
It is **not** a `@Component` (validators are not component-scanned):
Spring Boot's `LocalValidatorFactoryBean` uses a `SpringConstraintValidatorFactory`,
which creates each validator through the application context
(`AutowireCapableBeanFactory.createBean`), so constructor injection of Spring
beans works. Hibernate Validator then caches one instance per constraint and
shares it across threads.

```java
// validator/EditableProductIdValidator.java
@RequiredArgsConstructor
@Slf4j
public class EditableProductIdValidator
        implements ConstraintValidator<EditableProductId, String> {

    private final ProductLookupService productLookupService;  // Spring bean from rule/
    private final ProductEditabilityRule productEditabilityRule;  // domain rule bean

    @Override
    public void initialize(final EditableProductId annotation) {
        // Capture any annotation attributes here (see §2d: this.allowed = Set.of(annotation.allowed())).
    }

    @Override
    public boolean isValid(final String productId,
                           final ConstraintValidatorContext ctx) {
        if (StringUtils.isBlank(productId)) {
            return rejectWith(ctx, "Product ID must not be blank");
        }

        // delegate to an injected lookup / rule bean — never a database or remote call written directly in the validator (input-validation SKILL: domain rule beans)
        final String productType = productLookupService.getProductType(productId);

        // "unknown" and "not editable" give the SAME message: this runs before authorization, so it must not reveal
        // whether the product exists or what its type is (permissions §10)
        if (productType != null && productEditabilityRule.isEditable(productType)) {
            return true;
        }
        ctx.unwrap(HibernateConstraintValidatorContext.class)
                .addMessageParameter("productId", productId);   // parameter values are inserted literally, not re-interpolated
        return false;                                            // default violation: the annotation's message
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

    /**
     * The message is a Bean Validation *template*: `{...}` and `${...}` in it are interpolated. Request data is
     * attacker-controlled, so if you ever build a template from it (prefer addMessageParameter), escape it first —
     * otherwise `${...}` is evaluated and echoed back.
     */
    private static String escape(final String runtimeValue) {
        return runtimeValue == null ? "" : runtimeValue.replace("\\", "\\\\").replace("{", "\\{").replace("}", "\\}").replace("$", "\\$");
    }
}
```

Rules:
- **`initialize()`** must capture every annotation attribute you need at
  validation time. The annotation instance passed here is the one from the
  annotated element — that is where `allowed` (§2d) and other annotation
  parameters live.
- **`isValid()`** must return `false` + call `rejectWith(...)` when invalid, or
  return `true` when valid. Never throw inside `isValid()` for an expected
  failure — Hibernate Validator wraps it in `jakarta.validation.ValidationException`, which is **not** a violation and surfaces as a `500`.
  Catch what you expect and return `false`.
- **Never put request data into a violation template unescaped** (see `escape` above): `{...}` / `${...}` would be interpolated.
- Use `ctx.disableDefaultConstraintViolation()` + `buildConstraintViolationWithTemplate()`
  whenever you compute the message at runtime. For runtime *values* in the
  annotation's message, prefer `addMessageParameter` and keep the default
  violation. Skip both only when the annotation's static `message` is sufficient.
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
@RequestMapping("/api/v1/products")
@Validated  // REQUIRED on the controller — enables parameter-level validation
@RequiredArgsConstructor
public class ProductController {

    @PatchMapping("/{productId}")
    public ResponseEntity<ProductResponse> update(
            @PathVariable @EditableProductId String productId,
            @RequestBody @Valid UpdateProductRequest request) {
        // productId is already validated — no ad-hoc checks needed
        ...
    }
}
```

- `@Validated` on the controller class enables Spring's AOP method-validation proxy. **Spring Boot < 3.2:** without it, `@EditableProductId` on a
  `@PathVariable` is silently ignored. **Spring Boot 3.2+ (Spring Framework 6.1):** controller parameter constraints are validated without it and a
  failure raises `HandlerMethodValidationException` (a `400` via `ResponseEntityExceptionHandler`). Class-level `@Validated` switches to the AOP path,
  which raises `ConstraintViolationException` instead — it needs an explicit `400` handler (see the `exception-handling` template).
- `@Valid` on `@RequestBody` triggers nested Jakarta validation of DTO fields.
- Both `@Validated` (parameter constraints) and `@Valid` (nested DTO constraints)
  can be active on the same method.

### 2d. Annotation with extra attributes

When the same constraint is parameterised by a **static policy** — values
fixed where the annotation is written (e.g. "shipping method must be one of
the methods this endpoint supports"):

```java
// annotation/SupportedShippingMethod.java
@Constraint(validatedBy = {SupportedShippingMethodValidator.class})
@Target({ElementType.PARAMETER, ElementType.FIELD})
@Retention(RetentionPolicy.RUNTIME)
@Documented
public @interface SupportedShippingMethod {
    String[] allowed();             // required annotation attribute — the static policy

    String message() default "Shipping method ''{value}'' is not supported here";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}
```

```java
// Usage on controller parameter:
public ResponseEntity<ShipmentResponse> createShipment(
        @PathVariable String orderId,
        @RequestParam @SupportedShippingMethod(allowed = {"STANDARD", "EXPRESS"}) String shippingMethod) { ... }
```

The validator captures `allowed` in `initialize()` (`this.allowed = Set.of(annotation.allowed())`)
and checks membership in `isValid()`; on a miss it sets `{value}` with
`addMessageParameter("value", shippingMethod)` and returns `false`. A rule that depends on **other request
values** (e.g. "method X is available for the order's destination country") is
cross-field: write a Spring `Validator` (§3) instead of hard-coding request
values into annotation attributes.

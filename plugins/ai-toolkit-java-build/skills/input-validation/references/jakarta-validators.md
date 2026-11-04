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
    String message() default "Product with id '%s' is of type '%s' which is not editable";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}
```

Rules:
- **Always include `message`, `groups`, `payload`** — Jakarta requires them.
- Use a `%s`-style template in `message` when the violation text must include
  runtime values (product id, type, …); the validator formats it dynamically
  (§2c).
- `@Target` must include `ElementType.PARAMETER` to apply to controller method
  parameters (the most common case) and optionally `ElementType.FIELD` for DTO
  fields.
- Keep the annotation name a **noun phrase** describing what it asserts (e.g.
  `@EditableProductId`, `@ValidShippingMethod`) — not how it works.

### 2b. The validator class

The validator is a Spring `@Component` that implements
`ConstraintValidator<AnnotationType, ValueType>`. Spring's `LocalValidatorFactoryBean`
auto-discovers and injects Spring beans into `ConstraintValidator` implementations —
constructor injection works exactly as in any other Spring bean.

```java
// validator/EditableProductIdValidator.java
@Component
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
@Slf4j
public class EditableProductIdValidator
        implements ConstraintValidator<EditableProductId, String> {

    private final ProductLookupService productLookupService;  // Spring bean from rule/
    private final ProductEditabilityRule productEditabilityRule;  // domain rule bean

    private String messageTemplate;  // captured from annotation in initialize()

    @Override
    public void initialize(final EditableProductId annotation) {
        this.messageTemplate = annotation.message();
        // Capture any other annotation attributes (destinationCountry, shippingMethod, …) here.
        // Example: this.destinationCountry = annotation.destinationCountry();
    }

    @Override
    public boolean isValid(final String productId,
                           final ConstraintValidatorContext ctx) {
        if (StringUtils.isBlank(productId)) {
            return rejectWith(ctx, "Product ID must not be blank");
        }

        // a local / cached rule bean — never a database or remote call in the request path (input-validation SKILL: domain rule beans)
        final String productType = productLookupService.getProductType(productId);
        if (StringUtils.isBlank(productType)) {
            return rejectWith(ctx, String.format("Type for product '%s' could not be determined", escape(productId)));
        }

        if (productEditabilityRule.isEditable(productType)) {
            return true;
        }

        // Use the captured messageTemplate with runtime values
        return rejectWith(ctx, String.format(messageTemplate, escape(productId), escape(productType)));
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
     * The message is a Bean Validation *template*: `{...}` and `${...}` in it are interpolated. Request data (a path variable
     * here) is attacker-controlled, so escape it before it goes into a template — otherwise `${...}` is evaluated and echoed back.
     */
    private static String escape(final String runtimeValue) {
        return runtimeValue == null ? "" : runtimeValue.replace("\\", "\\\\").replace("{", "\\{").replace("}", "\\}").replace("$", "\\$");
    }
}
```

Rules:
- **`initialize()`** must capture every annotation attribute you need at
  validation time. The annotation instance passed here is the one from the
  annotated element — that is where `destinationCountry`, `shippingMethod`, and
  other annotation parameters live.
- **`isValid()`** must return `false` + call `rejectWith(...)` when invalid, or
  return `true` when valid. Never throw inside `isValid()` for an expected
  failure — Hibernate Validator wraps it in `jakarta.validation.ValidationException`, which is **not** a violation and surfaces as a `500`.
  Catch what you expect and return `false`.
- **Never put request data into a violation template unescaped** (see `escape` above): `{...}` / `${...}` would be interpolated.
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
@RequestMapping("/api/v1/products")
@Validated  // REQUIRED on the controller — enables parameter-level validation
@RequiredArgsConstructor(onConstructor = @__(@Autowired))
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

When the same constraint is parameterized (e.g. "is shipping method X available
to destination country Y"):

```java
// annotation/ValidShippingMethod.java
@Constraint(validatedBy = {ShippingMethodValidator.class})
@Target(ElementType.PARAMETER)
@Retention(RetentionPolicy.RUNTIME)
@Documented
public @interface ValidShippingMethod {
    String destinationCountry();    // required annotation attribute
    String shippingMethod();        // required annotation attribute

    String message() default "Order '%s' cannot be shipped with method '%s' to destination country '%s'";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}
```

```java
// Usage on controller parameter:
public ResponseEntity<ShipmentResponse> createShipment(
        @PathVariable @ValidShippingMethod(
                destinationCountry = "DE",
                shippingMethod     = "EXPRESS"
        ) String orderId) { ... }
```

The validator captures `destinationCountry` and `shippingMethod` in `initialize()`
and uses them in `isValid()`.

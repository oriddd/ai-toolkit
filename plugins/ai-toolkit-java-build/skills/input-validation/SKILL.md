---
name: input-validation
description: >
  Java / Spring Boot input validation — Jakarta ConstraintValidator for field/parameter rules, Spring Validator for
  cross-field rules, custom annotations, injected rule beans, @InitBinder registration. Use when writing or changing
  any validation rule; no ad-hoc guards. Theory: `validation-pattern`.
tier: must
applies_to: [rest, monolith]
depends_on: [code-structure, exception-handling, spring-boot-conventions, validation-pattern]
ships_templates: false
hitl: true
version: 1.3
last_reviewed: 2026-07-13
---

# Input Validation Skill
> **Pattern Foundation:** This skill is a concrete application of the `validation-pattern` skill. 
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
@Constraint(validatedBy = OrderLayoutValidator.class)
public @interface ValidOrderLayout { ... }

@Component
public class OrderLayoutValidator implements ConstraintValidator<ValidOrderLayout, String> {
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
│   └── (or policy/, domain/, etc. — name contextually)
└── config/
    └── ValidationConfig.java    # @ControllerAdvice that registers Spring Validators
```

Rules:
- **`annotation/`** contains only annotation interfaces — no logic.
- **`validator/`** contains validator implementations that *delegate* logic to
  `rule/` beans. Validators know how to produce constraint violations; they do
  not own business rule logic themselves.
- **`rule/`** (or `policy/`, `domain/`, etc.) contains pure Spring `@Component` beans 
  that express a single domain rule (`isProductEditable`, `isShippingMethodAvailable`, …). 
  These are injectable, unit-testable in isolation, and reusable across multiple
  validators. No Jakarta or Spring MVC imports allowed here — they speak the
  domain language only. **May call external services** (via injected clients) to
  fetch configuration or lookup data.
- **`config/`** holds `ValidationConfig` and nothing else.

## Reference map — load only the part you are working on

Sections below keep their numbers but live in `references/` so this file stays small. Read only the file you need; do not load them all.

| Sections | Topic | Load when | File |
| --- | --- | --- | --- |
| §2 | field / parameter-level validators | writing a custom constraint annotation and its `ConstraintValidator` | [`jakarta-validators.md`](./references/jakarta-validators.md) |
| §3, §4 | object / cross-field validators and `rule/` beans | writing a cross-field validator or a domain rule bean | [`spring-validators-and-rules.md`](./references/spring-validators-and-rules.md) |
| §5 | unit and slice tests for validators | testing validation code | [`testing.md`](./references/testing.md) |

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
- [ ] Add a `@MockitoBean` (Spring Boot 3.4+; replaces the deprecated `@MockBean`)
      for the validator (Spring style) or for the rule bean (Jakarta style) in
      affected controller component tests.

## Do / Don't

✅ Put all domain logic in `rule/` beans — validators are thin orchestrators.
✅ Use Jakarta `@Constraint` for parameter/field rules; Spring `Validator` for
   cross-field / object-level rules.
✅ Always call `ctx.disableDefaultConstraintViolation()` before
   `buildConstraintViolationWithTemplate(message)` when overriding the message
   at runtime.
✅ Add `@Validated` to the controller class when using parameter-level Jakarta
   constraints — on Spring Boot < 3.2 the annotation is silently ignored without
   it; on 3.2+ it selects the AOP path that raises `ConstraintViolationException`
   (mapped to 400 by `exception-handling`) — see `references/jakarta-validators.md` §2c.
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
❌ Never skip `@MockitoBean` for registered validators in controller component
   tests — the context will fail to load.

## Cross-references

- `exception-handling` — maps
  `ConstraintViolationException` and `MethodArgumentNotValidException` to 400
  `ProblemDetail`; must be set up for validation errors to appear correctly.
- `spring-boot-conventions` §4 — JSR-380
  `@Valid` / `@Validated` wiring on controllers.
- `code-structure` — package layout and layering
  rules the `validation/` package plugs into.
- `component-tests` — full-context `TestRestTemplate` tests for
  end-to-end validation path testing (the `@WebMvcTest` slice in §5c is the
  lighter web-layer check).
- `unit-tests` — testing rule beans and validators in
  isolation.


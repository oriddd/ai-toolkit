# Agent: New Validation Rule

> **Purpose:** Add a new input-validation rule (Jakarta `@Constraint` or
> Spring `Validator`) following the canonical three-layer pattern.

---

You are a backend-coding agent for a Java 21 / Spring Boot microservice.
The developer wants to add a **new validation rule**. You will produce the
annotation, the validator, the domain rule bean, and the tests.

## Skills to apply (in this order)

1. [`input-validation`](../skills/input-validation/SKILL.md) — the full
   pattern: annotation → validator → rule bean.
2. [`exception-handling`](../skills/exception-handling/SKILL.md) — the
   400 ProblemDetail mapping must be in place.
3. [`unit-tests`](../skills/unit-tests/SKILL.md) — rule bean (plain
   POJO), validator (mock ConstraintValidatorContext), component test.
4. [`component-tests`](../skills/component-tests/SKILL.md) — end-to-end
   400 HTTP response assertion.

## Decision: which style to use?

```
IF the rule applies to a single @PathVariable / @RequestParam / one DTO field
  AND it can be expressed as a boolean check on the value
→ USE Jakarta @Constraint + ConstraintValidator

IF the rule spans multiple fields in the same @RequestBody DTO
  OR depends on the combination of several values
→ USE Spring Validator + @InitBinder in ValidationConfig
```

## Generated file list

### Jakarta style
```
validation/
  annotation/<RuleName>.java          (e.g. @ValidEntityType)
  validator/<RuleName>Validator.java
  rule/<RuleName>Rule.java            (domain rule bean)
```
Add `@Validated` to the controller class if not already present.

### Spring Validator style
```
validation/
  validator/<Dto>Validator.java
  rule/<RuleName>Rule.java            (if extractable domain logic)
```
Add a field + `@InitBinder("lowerCamelDtoName")` to `ValidationConfig`.

## Checklist before returning

- [ ] Rule bean has no Jakarta/Spring MVC imports — pure domain logic.
- [ ] Validator captures annotation attributes in `initialize()`.
- [ ] `ctx.disableDefaultConstraintViolation()` called before custom
      message template.
- [ ] Parsers / lookups in the rule bean, never directly in `isValid()`.
- [ ] Controller carries `@Validated` (Jakarta style).
- [ ] `ValidationConfig` has scoped `@InitBinder("dtoName")` (Spring style).
- [ ] Unit test: rule bean as POJO, validator with mocked ctx.
- [ ] Component test: HTTP 400 + ProblemDetail body asserted.
- [ ] `@MockBean` for the validator added to affected `@WebMvcTest` tests.
- [ ] CHANGELOG updated.


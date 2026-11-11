---
name: new-validation
description: Java / Spring Boot — add a new input-validation rule (Jakarta `@Constraint` or Spring `Validator`) following the canonical three-layer pattern.
---

# Agent: New Validation Rule

> **Purpose:** Add a new input-validation rule (Jakarta `@Constraint` or
> Spring `Validator`) following the canonical three-layer pattern.

---

You are a backend-coding agent for a Java 21 / Spring Boot microservice.
The developer wants to add a **new validation rule**. You will produce the
annotation, the validator, the domain rule bean, and the tests.

## Skills to apply (in this order)

Load each skill with the Skill tool, by its qualified name, before applying it — do not work from memory. Also
load `ai-toolkit-quality:completion-gate` and `ai-toolkit-quality:code-hygiene` before you finish (see the gate below).

1. `ai-toolkit-java-build:input-validation` — the full
   pattern: annotation → validator → rule bean.
2. `ai-toolkit-java-build:exception-handling` — the
   400 ProblemDetail mapping must be in place.
3. `ai-toolkit-java-quality:unit-tests` — rule bean (plain
   POJO), validator (mock ConstraintValidatorContext).
4. `ai-toolkit-java-quality:component-tests` — end-to-end
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
  annotation/<RuleName>.java          (e.g. @ValidProductType)
  validator/<RuleName>Validator.java
  rule/<RuleName>Rule.java            (domain rule bean)
```
Put the annotation on the controller parameter (or on a field of a `@Valid` request body). Boot 3.5 validates it with
the built-in method validation — do **not** add class-level `@Validated` to the controller (it switches to
`ConstraintViolationException`; `input-validation` §2c). Only on Spring Boot < 3.2 is `@Validated` required.

### Spring Validator style
```
validation/
  validator/<Dto>Validator.java
  rule/<RuleName>Rule.java            (if extractable domain logic)
```
Add a field + `@InitBinder("lowerCamelDtoName")` to `ValidationConfig`.

## Commit policy and completion gate

Never `git commit`, `git push`, `git stash` or tag — leave the changes in the working tree until the developer asks.
Before reporting the task done, run the `ai-toolkit-quality:completion-gate` skill — all nine checks: scope, build, full
tests plus the PIT run, static analysis, standards (`ai-toolkit-java-quality:quality-review`), coverage of the changed
code, `ai-toolkit-quality:code-hygiene`, Sonar, docs — and finish with its evidence table. Commands are shown for Maven;
on a Gradle build use the project's wrapper equivalent (`./gradlew build`). Fix failures at the cause; never suppress or
weaken a check to get green. Return the evidence table to your caller unchanged, so it can relay it instead of running
the gate a second time.

## Checklist before returning

- [ ] Rule bean has no Jakarta/Spring MVC imports — pure domain logic.
- [ ] Validator captures annotation attributes in `initialize()`.
- [ ] `ctx.disableDefaultConstraintViolation()` called before custom
      message template.
- [ ] Parsers / lookups in the rule bean, never directly in `isValid()`.
- [ ] Jakarta constraints are actually enforced: built-in method validation, **no** class-level `@Validated` on the
      controller (Boot 3.5; `input-validation` §2c).
- [ ] `ValidationConfig` has scoped `@InitBinder("dtoName")` (Spring style).
- [ ] Unit test: rule bean as POJO, validator with mocked ctx.
- [ ] Component test: HTTP 400 + ProblemDetail body asserted.
- [ ] `@MockitoBean` for the validator / rule bean added to affected `@WebMvcTest` tests (`ai-toolkit-java-build:input-validation`, testing reference); full `@SpringBootTest` component tests keep the real rule and get any doubles from `ComponentTestConfiguration` (`ai-toolkit-java-quality:component-tests`).
- [ ] CHANGELOG updated — only when no release bot owns it (`ai-toolkit-workflow:release-versioning`).
- [ ] `ai-toolkit-quality:completion-gate` evidence table produced; nothing committed.

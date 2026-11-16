# Create-Repo Skill — Phase 3, remaining steps

Part of the [`create-repo`](../SKILL.md) skill. Step numbers are stable.

3a. **`api-design`** (+ **`openapi-first-codegen`** if the developer
   wants the spec to drive the code) → URL, status-code and error-format
   conventions for the first endpoints.
3b. **`input-validation`** → `validation/` package and `ValidationConfig` for
   the first request types.

11. **`integration-tests`** *(if any external dependency was added)* →
    produces `*IT.java` Testcontainer / WireMock tests under
    `@Tag("integration")` (Failsafe is already in the `ci` pom).

12. **`sdk-publishing`** *(only if the developer answered "this repo is a
    reusable library")* → adds the `META-INF/spring/...AutoConfiguration.imports`
    file, the `additional-spring-configuration-metadata.json`, and the
    `ApplicationContextRunner`-based slice tests.

13. **`quality-review`** → run the SOLID / conventions audit (every
    checklist item A–F, including quantitative thresholds) on the whole
    generated repo; surface the report to the developer. Block the hand-off
    (Phase 6) if there are unresolved `FAIL`s.

15. **`release-versioning`** → Conventional Commits + release automation.
16. **`documentation-and-adr`** → ADR-0001 under `docs/adr/`, `docs/ARCHITECTURE.md`.
17. **`context-maintenance`** → the `context/` folder.

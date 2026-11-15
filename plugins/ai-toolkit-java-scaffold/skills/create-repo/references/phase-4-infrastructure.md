# Create-Repo Skill — Phase 4 common project infrastructure

Part of the [`create-repo`](../SKILL.md) skill. Section names are stable; other skills cite them.

## Phase 4 – Common project infrastructure

Always create these files at the repo root:

- **`README.md`** – use [`templates/README.md.tmpl`](../templates/README.md.tmpl);
  populate the title, service description, build/run sections.
- **`.gitignore`** – use [`templates/gitignore.tmpl`](../templates/gitignore.tmpl).
- **`renovate.json`** – `{"extends":["config:recommended"]}` (`config:base` is the old name).
- **`.editorconfig`** – use [`templates/editorconfig.tmpl`](../templates/editorconfig.tmpl).
- **`CODEOWNERS`** (`.github/CODEOWNERS`) – single line: `* <codeowner>`.
- **Maven wrapper** – run `mvn -N wrapper:wrapper` so `./mvnw` and
  `.mvn/wrapper/` exist (the `.gitignore` already keeps the wrapper jar).
- **Logging** – structured JSON comes from `observability` (step 7a); write a `logback-spring.xml`
  only if it needs encoder options, never a second, minimal one here.
- **`lombok.config`** – `lombok.addLombokGeneratedAnnotation = true`, so Jacoco and PIT skip Lombok-generated code.
- **`src/test/resources/application-component-test.yaml`** – only the
  test-friendly overrides for the `component-test` profile (in-memory
  clients, dummy credentials; with auth = yes `spring.security.oauth2.resourceserver.jwt.issuer-uri:
  https://issuer.example.test`, or every component test fails on the unresolved `${JWT_ISSUER_URI}`). Never name it `application.yaml`: a test
  `application.yaml` replaces the main one instead of adding to it
  (`component-tests` §3).

Profiles (`spring-boot-conventions`): no profile = defaults in
`application.yaml`; `local` = `application-local.yaml` (local-dev-experience);
`component-test` = test-only overrides; `k8s` / `prod` = set by the Helm chart
through `springProfilesActive` (`cd`).
- **`postman/`** – empty placeholder collection
  `{{repoName}}.postman_collection.json` with one example request hitting
  `{{contextPath}}/actuator/health`.

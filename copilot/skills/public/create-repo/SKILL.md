---
name: create-repo
description: Human-in-the-loop scaffolder that creates a brand-new Java/Spring Boot microservice repository. Prompts the user for project metadata, then applies the ci, cd and code-structure skills to produce a fully working repo (Jenkinsfile, Dockerfile, pom.xml, Helm chart, package skeleton, application.yaml, README, .gitignore, renovate.json).
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: [project-types, code-structure, ci, cd, local-dev-experience]
ships_templates: true
hitl: true
version: 1.0
last_reviewed: 2026-06-28
---

# this Create-Repo Skill (HITL)

This is the **entry-point** skill for bootstrapping a new microservice.
It is intentionally **Human-in-the-Loop**: the agent must collect answers from
the developer before generating any files.

## Phase 1 – Interview the developer

Ask the questions below. **Do not assume defaults silently** – confirm them
back to the user before proceeding. Group the questions and present them in a
single round if your tool supports it.

### Required

| # | Question | Stored as |
| - | -------- | --------- |
| 1 | Repository / artifact name (kebab-case, e.g. `my-service`)? | `repoName`, `artifactId` |
| 2 | Human-readable service name (e.g. `Foo Service`)? | `serviceDisplayName` |
| 3 | Java base package (e.g. `com.example.foo`)? | `basePackage` |
| 4 | Spring Boot `server.servlet.context-path` (e.g. `/foo-service`)? | `contextPath` |
| 5 | Container port (default `8800`)? | `appPort` |
| 6 | Codeowner email for Jenkins notifications? | `codeowner` |
| 7 | Latest `org.springframework.boot:spring-boot-starter-parent` BOM version? | `springBootVersion` |
| 8 | Target Kubernetes image registry (default `your-registry.example.com/<org> | `imageRegistry` |

### Optional (offer with sensible defaults)

| # | Question | Default |
| - | -------- | ------- |
| 9 | Does the service require **authentication / JWT**? | yes → include `permission/` package |
| 10 | Does it require **per-request metrics**? | yes → include `monitor/` skeleton |
| 11 | Does it call other this services via HTTP? | yes → include `client/` package |
| 12 | Resource requests / limits (CPU + memory)? | `1/2 CPU`, `4Gi/8Gi` mem |
| 13 | Max replicas for HPA? | `5` |
| 14 | External dependencies (MinIO, Kafka, Redis, Postgres, Elasticsearch…)? | none |
| 15 | Additional system packages required in the Docker image? | none |
| 16 | Initial Git remote URL (to `git remote add origin`)? | skip |

After collecting answers, **summarize them back to the user** and ask for
explicit confirmation before generating files.

## Phase 2 – Derived values

Compute and store these from the answers:

- `applicationClassName` = PascalCase(`repoName` minus any common prefix and
  the `-service` suffix) + `Application`
  (e.g. `my-foo-bar-service` → `FooBarApplication`).
- `chartName` = `repoName`.
- `basePackagePath` = `basePackage` with `.` replaced by `/`.
- `groupId` = first two segments of `basePackage` (e.g. `com.example`).

## Phase 3 – Generate the repository

Execute the following skills in order. Each one is documented in its own
`SKILL.md` – follow it strictly.

1. **`ci`** → produces `Jenkinsfile`, `Dockerfile`, `pom.xml`.
2. **`code-structure`** → produces the `src/main/java/<basePackagePath>/`
   package skeleton, `<applicationClassName>.java`, `application.yaml`,
   `logback-spring.xml`. Includes `permission/` and/or `monitor/` skeletons
   only when the developer opted in (Phase 1 #9 / #10). Generates the
   `ArchitectureTest` (ArchUnit) under `src/test/java`.
3. **`spring-boot-conventions`** → wires `@ConfigurationProperties`,
   profiles, validation, springdoc OpenAPI, the `Clock` bean and the
   `TaskExecutor` config. Adds `@ConfigurationPropertiesScan` to the
   application class.
4. **`exception-handling`** → produces the domain exception hierarchy,
   `ExceptionMessages` catalogue, and the `@RestControllerAdvice` extending
   `ResponseEntityExceptionHandler`.
5. **`permissions`** *(if Phase 1 #9 = yes)* → fills in the `permission/`
   package with `PermissionsHandler`, `PermissionsCheckStrategy` and the
   concrete strategies for the selected `CallerContext` values.
6. **`external-client`** *(once per external HTTP/gRPC dependency the
   developer named in Phase 1 #11 / #14)* → produces the SDK-style
   `client/<dep>/` sub-package (`*Config + *Client + *RequestBuilder +
   *ResponseHandler + *Constants + Adapter + Decorator stack +
   Resilience4j config`).
7. **`health-indicator`** *(once per downstream dependency)* → adds an
   `AbstractReadinessIndicator` subclass per dependency, the `WebClient`
   config, env vars in Helm and the `readiness` health group entry in
   `application.yaml`. This sub-skill is itself HITL — let it ask its own
   questions per dependency.
8. **`cd`** → produces `helm-chart/` with `Chart.yaml`, `values.yaml`,
   `templates/_helper.tpl`, `deployment.yaml`, `service.yaml`, `hpa.yaml`,
   `serviceAccount.yaml`, `servicemonitor.yaml`, and `secret.yaml` (only when
   external dependencies require credentials – Phase 1 #14).
9. **`unit-tests`** → for every class produced in the previous steps,
   generate a meaningful `*Test.java` next to it; add the ArchUnit
   `ArchitectureTest` and the PIT mutation-testing plugin to `pom.xml`.
10. **`component-tests`** → produce one
    `<UseCase>ComponentTest.java` per public endpoint plus the shared
    `ComponentTestConfiguration` (and any opt-out `@TestConfiguration`s for
    heavy `@PostConstruct` beans) with deterministic fakes for every
    collaborator added in the previous steps.
11. **`integration-tests`** *(if any external dependency was added)* →
    produces `*IT.java` Testcontainer / WireMock tests under
    `@Tag("integration")` and wires `maven-failsafe-plugin` in `pom.xml`.
12. **`sdk-publishing`** *(only if the developer answered "this repo is a
    reusable library")* → adds the `META-INF/spring/...AutoConfiguration.imports`
    file, the `additional-spring-configuration-metadata.json`, and the
    `ApplicationContextRunner`-based slice tests.
13. **`quality-review`** → run the SOLID / conventions audit (33 items
    including quantitative thresholds) on the whole generated repo; surface
    the report to the developer. Block the hand-off (Phase 6) if there are
    unresolved `FAIL`s.

## Phase 4 – Common project infrastructure

Always create these files at the repo root:

- **`README.md`** – use [`templates/README.md.tmpl`](./templates/README.md.tmpl);
  populate the title, service description, build/run sections.
- **`.gitignore`** – use [`templates/.gitignore.tmpl`](./templates/gitignore.tmpl).
- **`renovate.json`** – `{"extends":["config:base"]}`.
- **`.editorconfig`** – use [`templates/.editorconfig.tmpl`](./templates/editorconfig.tmpl).
- **`CODEOWNERS`** (`.github/CODEOWNERS`) – single line: `* <codeowner>`.
- **`src/main/resources/logback-spring.xml`** – minimal config wiring
  `spring-boot-starter-logging`.
- **`src/test/resources/application.yaml`** – mirrors the main one but with
  test-friendly defaults (in-memory clients, dummy credentials).
- **`postman/`** – empty placeholder collection
  `{{repoName}}.postman_collection.json` with one example request hitting
  `{{contextPath}}/actuator/health`.

## Phase 5 – Validate

Run, in order, and surface output to the user:

1. `mvn -q -DskipTests package` – verify the project compiles.
2. `mvn -q test` – verify the (empty) test suite is green.
3. `helm lint helm-chart` – verify the chart is valid.
4. `helm template helm-chart` – verify the manifests render.

If any step fails, **stop and report** – do not try to silently patch.

## Phase 6 – Hand-off

Print a short summary:

- Files created (grouped by skill).
- Next steps the developer must do manually:
  - Create the GitHub repo and push (`git init && git add . && git commit -m "chore: bootstrap" && git remote add origin <url> && git push -u origin main`).
  - Register the service in the this umbrella Helm chart.
  - Update the Jenkins job DSL to track the new repo.
  - Fill in the README "Overview" section.

## HITL guardrails

- **Never** generate files until Phase 1 questions are answered AND the
  developer has explicitly confirmed the summary.
- **Never** overwrite existing files in the target directory without asking.
- If running inside an existing repo, list which files would be overwritten and
  request per-file approval.
- If the developer requests a non-standard deviation (e.g. different parent
  POM, runtime), flag it as a deviation in the final summary so reviewers can
  spot it.

## 7. Templates

- [`README.md.tmpl`](./templates/README.md.tmpl) — Standard repository README.
- [`.gitignore.tmpl`](./templates/gitignore.tmpl) — Java/Maven/IntelliJ gitignore.
- [`.editorconfig.tmpl`](./templates/editorconfig.tmpl) — Project-wide formatting rules.

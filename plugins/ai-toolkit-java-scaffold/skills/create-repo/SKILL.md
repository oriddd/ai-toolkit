---
name: create-repo
description: >
  Java / Spring Boot repository scaffolder — asks for project metadata, then applies ci, cd and code-structure to
  produce Jenkinsfile, Dockerfile, pom.xml, Helm chart, package skeleton and README. Use only to create a brand-new
  repository, never to change an existing one.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: [project-types, code-structure, ci, cd, local-dev-experience]
ships_templates: true
hitl: true
version: 1.0
last_reviewed: 2026-11-11
---

# Create-Repo Skill (HITL)

This is the **entry-point** skill for bootstrapping a new microservice.
It is intentionally **Human-in-the-Loop**: the agent must collect answers from
the developer before generating any files. Run it in the **main session**: a
subagent cannot ask the developer, so a subagent that is handed this skill
returns the Phase 1 question list (and any assumptions) to its caller instead
of generating files.

The generated code targets **Spring Boot 3.5.x**, the version every Java skill
in this toolkit is written and verified against.

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
| 6 | Codeowner email for CI notifications? | `codeowner` |
| 7 | `org.springframework.boot:spring-boot-starter-parent` version — the latest **3.5.x** (default: latest 3.5.x patch)? Reject any other major/minor: the skills are written for Boot 3.5, and a 4.x parent does not compile with them. | `springBootVersion` |
| 8 | Target Kubernetes image registry (default `your-registry.example.com/<org>`)? | `imageRegistry` |
| 9a | Is this a **deployable service** or a **reusable library / SDK** (`project-types` Type D)? | `projectKind` (`service` / `library`) |

### Optional (offer with sensible defaults)

| # | Question | Default | Stored as |
| - | -------- | ------- | --------- |
| 9 | Does the service require **authentication / JWT**? | no default — ask (yes → include `permission/` package and Spring Security) | `auth` |
| 10 | Does it require **per-request metrics**? | no default — ask (yes → include `monitor/` skeleton) | `requestMetrics` |
| 11 | Does it call other internal services via HTTP? | no default — ask (yes → include `client/` package) | `httpClients` |
| 12 | Resource requests / limits (CPU + memory)? | requests `500m` / `512Mi`, limits `1` / `1Gi` | `resources.requests.cpu`, `resources.requests.memory`, `resources.limits.cpu`, `resources.limits.memory` |
| 13 | Max replicas for HPA? | `5` | `autoscaling.maxReplicas` |
| 14 | One-sentence service description for the README? | `{{serviceDisplayName}}` | `oneLineDescription` |
| 15 | Non-root UID / GID the pod runs as (must be able to read the image's files)? | `1000` | `runAsUser`, `runAsGroup`, `fsGroup` (also the image user in the Dockerfile) |
| 16 | External dependencies (MinIO, Kafka, Redis, Postgres, Elasticsearch…)? | none | `dependencies` (list of name + type) |
| 17 | Additional system packages required in the Docker image? | none (the `RUN apk add` line stays commented out) | `extraSystemPackages` |
| 18 | Initial Git remote URL (to `git remote add origin`)? | skip | `gitRemote` |
| 19 | Jenkins credentials ids for the image registry and the NVD API key used by dependency-check (Jenkins CI only)? | `registry-credentials`, `nvd-api-key` | `registryCredentialsId`, `nvdApiKeyCredentialsId` |

Variables that are **not** asked (`extraEnv`, `extraVolumes`, `credentials.existingSecret`,
`springProfilesActive`) are per-environment Helm values, not scaffold placeholders — see `cd` "Inputs".

When `project-types` ran first, use its answers as the defaults here, and ask
only what it did not settle.

After collecting answers, **summarize them back to the user** and ask for
explicit confirmation before generating files.

## Phase 2 – Derived values

Compute and store these from the answers:

- `applicationClassName` = PascalCase(`repoName` minus the `-service`
  suffix) + `Application` (e.g. `foo-bar-service` → `FooBarApplication`,
  `my-foo-bar-service` → `MyFooBarApplication`). Show it in the Phase 1
  summary so the developer can change it (e.g. drop a team prefix).
- `chartName` = `repoName`.
- `basePackagePath` = `basePackage` with `.` replaced by `/`.
- `groupId` = first two segments of `basePackage` (e.g. `com.example`).

## Phase 3 – Generate the repository

Execute the following skills in order. Each one is documented in its own
`SKILL.md` – follow it strictly.

1. **`ci`** → produces `Jenkinsfile`, `Dockerfile`, `pom.xml`. The `pom.xml`
   template already carries Lombok (`<optional>true</optional>`, needed by
   `@Slf4j` / `@RequiredArgsConstructor` in the generated code), the Jacoco
   `check` gate (85 % line / 75 % branch per class), Failsafe and PIT (≥ 75 %).
   Add `spring-boot-starter-security` only when Phase 1 #9 = yes.
   **Library (`projectKind = library`, Type D):** produce only `pom.xml`
   (no `Jenkinsfile` image stages, no `Dockerfile`), and remove the
   `spring-boot-maven-plugin` repackage — a fat jar is not usable as a
   dependency (or set `<classifier>exec</classifier>` if the library also
   ships a runnable demo).
2. **`code-structure`** → produces the `src/main/java/<basePackagePath>/`
   package skeleton, `<applicationClassName>.java`, `application.yaml`.
   Includes `permission/` and/or `monitor/` skeletons
   only when the developer opted in (Phase 1 #9 / #10), and creates only the
   packages the service populates. Generates the `ArchitectureTest`
   (ArchUnit) under `src/test/java` — the only place it is produced.
3. **`spring-boot-conventions`** → wires `@ConfigurationProperties`,
   profiles, validation, springdoc OpenAPI, the `Clock` bean and the
   `TaskExecutor` config. Adds `@ConfigurationPropertiesScan` to the
   application class.
3a. **`api-design`** (+ **`openapi-first-codegen`** if the developer
   wants the spec to drive the code) → URL, status-code and error-format
   conventions for the first endpoints.
3b. **`input-validation`** → `validation/` package and `ValidationConfig` for
   the first request types.
4. **`exception-handling`** → produces the unchecked domain exception
   hierarchy in `{{basePackage}}.exception` (`BaseDomainException extends
   RuntimeException` with `errorCode`; `BadRequestException` 400,
   `ForbiddenException` 403, `NotFoundException` 404,
   `UnsupportedApiVersionException` 406, `ConflictException` 409,
   `TooManyRequestsException` 429, `UnavailableException` 503,
   `DependencyException` 500), the `ExceptionMessages` catalogue in
   `exception.constants`, and the `@RestControllerAdvice`
   `GlobalExceptionHandler` in `exception.handler`, extending
   `ResponseEntityExceptionHandler`.
5. **`permissions`** *(if Phase 1 #9 = yes)* → fills in the `permission/`
   package with `PermissionsHandler`, `PermissionsCheckStrategy` and the
   concrete strategies for the selected `CallerContext` values.
6. **`external-client`** *(once per external HTTP/gRPC dependency the
   developer named in Phase 1 #11 / #16)* → produces the SDK-style
   `client/<dep>/` sub-package. This sub-skill is itself HITL — let it ask
   its §0 pattern-selection questions per dependency and generate the
   pattern the developer picks (Simple Wrapper / Lite Client / Full 5-Layer),
   plus its Resilience4j retry / circuit-breaker config (external-client §10).
6a. **Per Phase 1 #16 dependency type** — route each one to its skill:
   - Postgres / any SQL DB → **`persistence`** (entities, repositories, Flyway
     with `flyway-database-postgresql` for Postgres).
   - Kafka / RabbitMQ → **`messaging`** (idempotent consumer, DLQ, outbox).
   - Redis / cache, object store (MinIO / S3), search, secrets → **`pluggable-architecture`**
     (an `spi/` port + `adapter/<capability>/<vendor>/`) and
     **`adapter-contract-tests`** (one TCK per port).
   - Another HTTP service → `external-client` (step 6).
7. **`health-indicator`** *(once per downstream dependency)* → adds an
   `AbstractReadinessIndicator` subclass per dependency, the client
   config, env vars in Helm and the `readiness` health group entry in
   `application.yaml`. This sub-skill is itself HITL — let it ask its own
   questions per dependency.
7a. **`observability`** → JSON `logback-spring.xml` with MDC correlation IDs
   (guild #11), Micrometer / Prometheus and tracing. **`request-metrics`**
   when Phase 1 #10 = yes; with #9 auth = no, generate it without `ClientIdParser`, its interceptor and the
   `clientId` tag (`request-metrics` parsers-and-helpers §6) — those classes need Spring Security.
7b. **`security-hardening`** → security headers, CORS, secret handling
   (secrets as `${VAR}` with no default).
7c. **`graceful-shutdown`** → `server.shutdown=graceful` +
   `spring.lifecycle.timeout-per-shutdown-phase` and the shutdown test.
8. **`cd`** *(services only; skip for a library)* → produces `helm-chart/` with `Chart.yaml`, `values.yaml`,
   `templates/_helpers.tpl`, `deployment.yaml`, `service.yaml`, `hpa.yaml`,
   `pdb.yaml`, `serviceAccount.yaml`, `servicemonitor.yaml`, and `secret.yaml`
   (credentials only when external dependencies require them – Phase 1 #16).
   Render every `.tmpl` with the cd skill's **two-step process** ("Rendering
   the templates (two steps)"): substitute the `{{…}}` scaffold placeholders
   first, then unescape the Helm actions — never render a `.tmpl` with Helm
   directly. Placeholders come from Phase 1: `chartName`, `appPort`,
   `contextPath`, `imageRegistry`, `runAsUser` / `runAsGroup` / `fsGroup`
   (#15), `resources.*` (#12), `autoscaling.maxReplicas` (#13). The `ci`
   Dockerfile also uses `runAsUser` / `runAsGroup` (#15) and
   `extraSystemPackages` (#17); the Jenkinsfile uses `registryCredentialsId` and `nvdApiKeyCredentialsId` (#19).
9. **`unit-tests`** → for every class produced in the previous steps,
   generate a meaningful `*Test.java` next to it. The `ArchitectureTest`
   (step 2) and the PIT / Jacoco gates (`ci` pom, step 1) already exist —
   do not add them again.
10. **`component-tests`** → produce one
    `<UseCase>ComponentTest.java` per public endpoint plus the shared
    `ComponentTestConfiguration` (and any opt-out `@TestConfiguration`s for
    heavy `@PostConstruct` beans) with deterministic fakes for every
    collaborator added in the previous steps.
11. **`integration-tests`** *(if any external dependency was added)* →
    produces `*IT.java` Testcontainer / WireMock tests under
    `@Tag("integration")` (Failsafe is already in the `ci` pom).
12. **`sdk-publishing`** *(only if the developer answered "this repo is a
    reusable library")* → adds the `META-INF/spring/...AutoConfiguration.imports`
    file, the `additional-spring-configuration-metadata.json`, and the
    `ApplicationContextRunner`-based slice tests.
12a. **`static-analysis`** → Spotless, SpotBugs (+ the starter
    `spotbugs-exclude.xml`), Error Prone / NullAway, `checkstyle.xml`, and
    `.mvn/jvm.config`.
13. **`quality-review`** → run the SOLID / conventions audit (every
    checklist item A–F, including quantitative thresholds) on the whole
    generated repo; surface the report to the developer. Block the hand-off
    (Phase 6) if there are unresolved `FAIL`s.
14. **`local-dev-experience`** → docker-compose for the Phase 1 #16
    dependencies, Makefile, pre-commit hooks; dev settings in
    `application-local.yaml` (the `local` profile).
15. **`release-versioning`** → Conventional Commits + release automation.
16. **`documentation-and-adr`** → ADR-0001 under `docs/adr/`, `docs/ARCHITECTURE.md`.
17. **`context-maintenance`** → the `context/` folder.

## Phase 4 – Common project infrastructure

Always create these files at the repo root:

- **`README.md`** – use [`templates/README.md.tmpl`](./templates/README.md.tmpl);
  populate the title, service description, build/run sections.
- **`.gitignore`** – use [`templates/gitignore.tmpl`](./templates/gitignore.tmpl).
- **`renovate.json`** – `{"extends":["config:recommended"]}` (`config:base` is the old name).
- **`.editorconfig`** – use [`templates/editorconfig.tmpl`](./templates/editorconfig.tmpl).
- **`CODEOWNERS`** (`.github/CODEOWNERS`) – single line: `* <codeowner>`.
- **Maven wrapper** – run `mvn -N wrapper:wrapper` so `./mvnw` and
  `.mvn/wrapper/` exist (the `.gitignore` already keeps the wrapper jar).
- **`src/main/resources/logback-spring.xml`** – produced once, by
  `observability` (step 7a: JSON + MDC, guild #11); do not write a second,
  minimal one here.
- **`src/test/resources/application-component-test.yaml`** – only the
  test-friendly overrides for the `component-test` profile (in-memory
  clients, dummy credentials). Never name it `application.yaml`: a test
  `application.yaml` replaces the main one instead of adding to it
  (`component-tests` §3).

Profiles (`spring-boot-conventions`): no profile = defaults in
`application.yaml`; `local` = `application-local.yaml` (local-dev-experience);
`component-test` = test-only overrides; `k8s` / `prod` = set by the Helm chart
through `springProfilesActive` (`cd`).
- **`postman/`** – empty placeholder collection
  `{{repoName}}.postman_collection.json` with one example request hitting
  `{{contextPath}}/actuator/health`.

## Phase 5 – Validate

Run, in order, and surface output to the user:

1. `./mvnw -q spotless:apply` – format the generated code and sort the pom,
   or the Spotless check in step 2 fails.
2. `./mvnw -q verify` – compiles, runs the generated unit, component and
   architecture tests, Failsafe ITs, and the Jacoco, PIT, SpotBugs, Checkstyle
   and Error Prone gates — the same build CI runs. (ITs need Docker; if it is
   not available, report them as not verified rather than skipping silently.)
3. `helm lint helm-chart` – verify the chart is valid (services only).
4. `helm template helm-chart` – verify the manifests render (services only).

If any step fails, **stop and report** – do not try to silently patch.

## Phase 6 – Hand-off

Print a short summary:

- Files created (grouped by skill).
- Next steps the developer must do manually:
  - Create the GitHub repo and push (`git init -b main && git add . && git commit -m "chore: bootstrap" && git remote add origin {{gitRemote}} && git push -u origin main`). The agent never runs these; the developer does.
  - Register the service in your deployment repo, if you have one.
  - Update your CI job definition, if applicable.
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

## Templates

- [`README.md.tmpl`](./templates/README.md.tmpl) — Standard repository README.
- [`gitignore.tmpl`](./templates/gitignore.tmpl) — Java/Maven/IntelliJ gitignore (written as `.gitignore`).
- [`editorconfig.tmpl`](./templates/editorconfig.tmpl) — Project-wide formatting rules (written as `.editorconfig`).

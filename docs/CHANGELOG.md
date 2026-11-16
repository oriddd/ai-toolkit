# Changelog

All notable changes to this catalogue will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Restored original conventions (2026-11-16)

- Domain exceptions are checked again (`BaseDomainException extends Exception`), as in the user-tested originals. `GlobalExceptionHandler` maps both checked and unchecked exceptions (domain handler plus a catch-all 500). Checked exceptions do not roll back `@Transactional` by default, so every `@Transactional` carries `rollbackFor = Exception.class`, enforced by `ArchitectureTest`. New `exception-handling/references/checked-exceptions.md`.
- Constructor injection uses `@RequiredArgsConstructor(onConstructor = @__(@Autowired))` again, so a class with several constructors still injects.
- `external-client` asks which HTTP transport to use and shows a `RestClient` / `WebClient` comparison with a recommendation; `RestClient` stays the default.
- Proved on a Spring Boot 3.5.16 service (Error Prone + NullAway at ERROR): 55 tests pass, including checked and unchecked error mapping, rollback with and without `rollbackFor`, and the idempotent consumer.

## [2.4.0] - 2026-11-15

### Independent review fix round (2026-11-15)
Three independent reviewers rated `main` 7/10 (Java 7, Python 8, React Native 6.5). Every HIGH and MEDIUM finding was
verified against the files and fixed, each change proven by a build, type-check or run.
- **Java:**
  - `ExceptionMessages` template compiles again (a duplicated `@Nullable` broke every scaffolded service).
  - `external-client`'s Full 5-Layer transport uses `RestClient` `exchange` + `handleResponse` (was `WebClient` +
    `.block()` on the servlet stack); the reactive form stays for WebFlux callers. New §6b: outbound OAuth2 client
    credentials. Timeouts keep Boot's auto-detected HTTP client and `spring.http.client.*`.
  - One strategy contract everywhere (`getSupported<X>()`, registry indexed at startup); Kafka consumers/producers
    live in `messaging/consumer|producer` and ArchUnit layers them.
  - No `return null` from non-`@Nullable` methods in examples (NullAway-clean); API versions: unknown URI version → 404,
    unserved `Accept` version → 406.
  - `create-repo`: Spring Boot 3.5 stays the default, 4.x is an explicit opt-in (README records the decision);
    native structured logging; `lombok.config`.
  - Helm chart rolls on Secret change, renders the PDB by default (`minReplicas: 2`), spreads across zones.
  - Error Prone 2.52, NullAway 0.14.3, SpotBugs plugin 4.10.5.0, JaCoCo 0.8.16 (build-tested).
- **Python:** baseline Python 3.14 (3.12+); new `python-graceful-shutdown` skill; one active outbox relay by default
  (two `SKIP LOCKED` relays reordered one aggregate's events on a real PostgreSQL); ownership check after load in
  `python-new-endpoint`; CORS allows PUT/PATCH/DELETE + `If-Match` and exposes `ETag`; `validation` layer in
  import-linter; `uv init --package` skeleton; migration round-trip test.
- **React Native:** Expo Router is the default structure (React Navigation documented as the alternative); app
  version/build read at runtime (an unset `EXPO_PUBLIC_*` crashed production EAS builds at launch); `mapHttpError`
  honours the server's problem `code`; request timeout + abort signal; single-flight token refresh; Maestro
  `clearKeychain` on iOS; feature-internal import direction enforced by ESLint.
- **Neutral:** `documentation-and-adr`, `context-maintenance` and `uml-diagram` are language-neutral (per-language
  skill table) and agree on one diagram location; context templates mark SLO/DR sections "required for services";
  `release-versioning` accepts an existing Keep-a-Changelog file; HOW-TO no longer lists a check that always fails.
- **Evals:** behaviour cases for all 10 language-neutral skills (were 4); agent cases grant Write/Edit and grade the
  agent's output (the file it must write, or `file:line` in a review), plus a case that does not name the agent;
  near-miss negatives for the neutral plugins. CI also runs weekly so freshness fails before it fails a PR.
- **Second re-review (Java 6.5, Python 8, React Native 7.5, repo 7), every finding fixed with a before/after proof:**
  - Java: scaffolded services start again — `HttpCacheProperties` is conditional like its config (any non-http cache
    provider failed to boot) and `spring-boot-starter-oauth2-resource-server` is required with auth (startup
    `NoClassDefFoundError`); `create-repo` generates a default-profile context-load test. `golden-path` #20/#22/#23 agree
    with the skills (Spring Kafka/AMQP are accepted facades; no class-level `@Validated` on Boot 3.2+; `RestClient`
    `exchange`). New `ProblemDetailSecurityHandler` (401/403 as problem+json, `security.auth.failure` metric); SSRF
    host allow-list interceptor; rate limits never thrown from a filter; `$ref` enums with a scanned converter package;
    readiness only for hard dependencies; `sdk-publishing` on `RestClient`; existence checks on the authorized id run
    after authorization; `OutboxEntity` versioned and `Clock`-driven; Spotless 3.11, google-java-format 2.0,
    Checkstyle 14.4, PIT 1.30.2 (`withHistory` removed), archunit-junit5 in the ci pom.
  - Python: new `python-cd` (Helm chart: api + worker, migration hook Job, hardened pods, HPA/PDB, ServiceMonitor,
    NetworkPolicy); stdlib tracebacks rendered in JSON logs; worker heartbeat liveness and immediate idle shutdown;
    `--proxy-headers` with a required `FORWARDED_ALLOW_IPS`; scheduled `pip-audit`; 202 job resource; local run.
  - React Native: new `react-native-app-config-and-updates` and `react-native-permissions-and-push`; the detail screen
    obeys its own boundaries; server field-error codes map to messages; signup goes through the feature `api/`; error
    class names survive minification.
  - Repo: agent evals are granted Write/Edit (`run-evals.sh agents`) and grade a successful subagent write, one grader
    per key skill; Spring Boot 3.5's end of OSS support (2026-06-30) is stated in README and `create-repo`; the
    pre-push hook works without the private blocklist; CI actions bumped with Dependabot; `check-versions.sh` counts
    `plugin.json` description/dependency changes.
- **Eval results (2026-11-16, Claude Code 2.1.311), measured on this release, not carried over from 2.3.0:**
  - Routing: 112/112 (every skill's trigger case loads its skill; negatives, including the near-miss ones, load none).
  - Agents (25 cases, one run each, with Write/Edit granted, graded on a successful subagent write and one skill rule in the
    written file): 24 fully pass. React Native `new-screen` scores 0.80: it wrote a screen without `accessibilityRole`.
    Two cases passed only after their prompts told the agent that nobody can answer questions (a subagent stops and asks
    otherwise, by design).
  - Behaviour (with vs without the plugin, 3 runs each arm): every case was last measured in this release and shows a lift;
    cases whose graders or skills changed in the final rounds were re-run, unchanged ones were not repeated. Lifts quoted for
    pruned graders are optimistic (scored on the same runs). Lowest: React Native `git-commit-conventions--react-native`
    +0.25, `react-native-app-config-and-updates` and `react-native-permissions-and-push` below +0.30 before their graders were
    rewritten; the trimmed `uml-diagram` +0.40 and `context-maintenance` +0.93 keep their lift.
  - Not exercised by any eval: the commit guard and routing hooks (`tools/test-hooks.sh`, about 250 cases), `scaffold-repo`
    (interactive), device/EAS/push behaviour, and the Boot 4 variants beyond the listed templates.
- **Final independent review (Java 8, Python 8.5, React Native 7.5, neutral 7.5, repo 8); every finding fixed with a proof:**
  - Java: with persistence the context-load test is a Testcontainers `ApplicationContextIT` (a default-profile test cannot
    pass without a database); the datasource is defined end to end (`persistence` §3b, local profile, README rows, Helm
    `database:` block); yaml snippets say to merge under the existing top-level keys (appending a second `spring:` block broke
    every context); `spring-kafka` / `spring-boot-starter-amqp` are listed; every error body has an `errorCode` (404, 405, 415
    included); auth=no + persistence compiles (`SystemAuditorAware`); `code-review` bans raw `RestClient` as well as `WebClient`.
  - Python/React Native: `python-ci` SHA-pins every action like `react-native-ci`; the Python review/feature/refactor agents load
    `python-cd` and `python-graceful-shutdown`; the `app.config.ts` snippet passes the skill's own ESLint gate.
  - Neutral: Python and React Native variants of the completion-gate, git-commit-conventions, parallel-delegation and
    pr-description evals; `commit-msg.sh` enforces length, trailing period and case; `pr-description` examples obey their
    rules; `parallel-delegation` falls back to `general-purpose` when an agent plugin is absent; `completion-gate` has an
    other-stack row; `update-context` bootstraps a missing `context/`; `uml-diagram` (580 → 203 lines) and
    `context-maintenance` (475 → 232) keep their rules and templates, with the tutorial text moved to `references/` (grouped
    section numbers and a few Java-flavoured example types reworded; the marketing headings are gone).
  - Repo: the 400 KB guard timing test allows 10 s (it flaked at 3 s under load); the setup guide's token figures are measured.
- **Executed, not just compiled** (Docker via Colima, a throwaway `kind` cluster; the shared cluster was never touched):
  - Java: 28 integration tests on real PostgreSQL, Kafka and Redis; the image runs non-root with a read-only root
    filesystem and drains an in-flight request on `docker stop`; the Helm chart installs on `kind`, rolls on a Secret
    change and served a looping client with 0 failures across two rollouts. Defects found by running and fixed: the
    chart's hard-coded AppArmor profile made the kubelet reject every pod (`appArmor.enabled` toggle); WireMock with
    Boot's default HTTP client sent an empty PUT body (`http2PlainDisabled`); a skill example used `StringUtils`
    without its dependency; a database-only integration test blocked ~45 s on an absent Kafka broker; the Kafka
    container class and retry-topic naming were undocumented.
  - Python: 22 integration tests on real PostgreSQL and Kafka (two relays keep per-aggregate order; the test fails
    without the lock); the image builds and drains on `docker stop`; the `python-cd` chart installs on `kind` with its
    migration hook (a failed migration leaves the old pods serving). Defects fixed: the chart failed to install on a
    cluster without Prometheus CRDs (monitors are now guarded by capability); `testcontainers.kafka` is deprecated
    (use `testcontainers.community.kafka`); `str(url)` masks the Alembic password. Unproven: HPA scaling, NetworkPolicy
    enforcement, the real `ghcr.io` pull, one transient 503 in 917 requests during one of three rolling updates.
- **Spring Boot 4.1.2 is a verified second target** (3.5 stays the default): the same rendered service passes the same
  26 tests on both (component tests, ArchUnit, default-profile boot, Postgres IT); the differences are in
  `spring-boot-conventions/references/spring-boot-4.md`. A real defect surfaced: with only the 3.5 class names, Boot 4
  silently started a database in component tests (the skill now lists both name sets). Not built on 4.x: Flyway,
  outbound OAuth2, springdoc, openapi-generator, Resilience4j, Bucket4j, ShedLock, Kafka retry against a broker.
- **Neutral plugins** are language-neutral: Java commands and names are per-language rows (Java / Python / React
  Native) in `documentation-and-adr`, `context-maintenance`, `git-commit-conventions`, `parallel-delegation`,
  `pr-description`, `uml-diagram`, `completion-gate` and `update-context`; their examples obey their own rules (commit
  subjects were run through `commit-msg.sh`, workflows through `actionlint` and Mermaid through its parser during review; CI does not enforce these); the quality plugin says what to
  do when installed alone.
- **Evals measure quality:** 16 behaviour cases got graders for rules a model does not follow unprompted (graders the
  baseline passes were removed; lifts after pruning are optimistic because they were scored on the same runs);
  `sonar-quality-gate` got a self-contained prompt; four graders threw on a JavaScript-regex incompatibility; the
  build no longer deletes eval results; `new-validation` now loads `validation-pattern`.
- **Final review (Java 7.5, Python 7.5, React Native 7.5, repo 7.5), every finding fixed with a before/after proof:**
  - Java: the static-analysis pom block is well-formed XML (a `--` inside a comment made Maven reject it); generated
    component tests set an issuer URI; `application-local.yaml`, the README and the Helm chart carry `JWT_ISSUER_URI` /
    `JWT_AUDIENCE`; `GlobalExceptionHandler` has tagged `[validation]` / `[security]` / `[persistence]` blocks with a
    tested strip recipe, so no-auth and no-DB scaffolds compile; an unreachable identity provider returns 503
    problem+json (new `IdentityProviderUnavailableFilter`), not a 500; the templates compile warning-free under
    Error Prone; `golden-path` #6 says an adapter is its port's client.
  - Python: `python-cd` pod labels no longer duplicate `app.kubernetes.io/name|instance` (strict YAML parsers rejected
    them); only `helm template` enforces the required `forwardedAllowIps`, not `helm lint`; `run_worker` exits non-zero
    when the relay or consumer crashes (it used to wait for SIGTERM forever); the relay beats a heartbeat; the worker
    serves `/metrics` with a PodMonitor.
  - React Native: workflow inputs go through `env`, not into the shell; actions are SHA-pinned; OTA publish is gated on
    `eas fingerprint:compare`; the push-registration snippet compiles.
  - Repo: eval results are never tracked (`evals/**/results/` ignored); `run-evals.sh all` runs the agent cases with
    Write/Edit and a scaffold; the review-agent grader is tied to the Agent result; agent graders check a skill rule in
    the written file; the validator fails when `marketplace.json` and the latest CHANGELOG release disagree.
- **Deliberate corrections of original rules** (substance kept, mechanism changed): `external-client` (`.block()` +
  `exchangeToMono` → `RestClient` `exchange`; same single non-2xx mapping and synchronous API) and the strategy registry
  (indexed by `getSupported<X>()` instead of iterating `canHandle`; same routing, add-a-strategy-never-touch-the-handler).
  Also corrected, each with a failing-then-passing proof: `permissions` requires the resource-server starter; downstream
  probes are readiness-only; `new-kafka-consumer` dedupes on the `event-id` header in the same transaction (no Redis
  store); `sdk-publishing` uses `RestClient`; the inline-enum "redundant validator" example uses a `$ref` enum;
  `feature-flags` keeps "close to the business logic" as one decision point per flag.

## [2.3.0] - 2026-11-11

### Audit fix round (2026-11-11)
- Java: about 50 verified fixes from an independent audit and a real build (Kafka DLT loop, lost domain events, `@Validated`
  on Boot 3.2+, `/api/v2` denied, NullAway/SpotBugs/Spotless build breaks, contract-test override, IT-only command, guard gaps).
- React Native: toolchain brought current (Jest 30, RNTL 14, ESLint 10, boundaries v7); a sample Expo SDK 58 app passes `verify`.
- Python: 17 fixes; new `python-external-client`, `python-security`, `python-messaging`; a sample FastAPI service passes `verify`.
- Evals generated from `tools/eval_cases/` by `tools/build-evals.py` (CI checks they are in sync); 44 behaviour cases.
- Agents load their skills first, before any clarifying question (they used to ask first and sometimes never loaded them).
- Results (Claude Code 2.1.311): routing 105/105 (76 triggers, 29 negatives); agents 24/24 cases pass; behaviour
  44 skills, all with a with/without lift (e.g. `permissions` 1.00 vs 0.00, `react-native-input-validation` 1.00 vs
  0.00, `python-error-handling` 0.80 vs 0.00, `react-native-ci` 1.00 vs 0.33).
  Open: `strategy-registry-pattern` 0.80 and `react-native-state-and-data` 0.80 (`safeParse` at the edge 0/3).
- Behaviour graders for `documentation-and-adr`, `messaging`, `resilience-patterns`, `graceful-shutdown`,
  `python-unit-tests` and `release-versioning` now check the skill's own rules instead of practices the model already
  follows (lift 0.00 → +0.80, +0.73, +0.60, +0.56, +0.33, +0.17). Regex graders can assert absence
  (`match: not_contains`, a third tuple field in `tools/eval_cases/behaviour.py`).
- The `test-writer` eval prompt now describes the fixture's hand-built `RestTemplate`; without it the main session
  rightly stopped to ask instead of delegating (now 2/2 graded runs delegate and load `unit-tests`).
- Clean Java rebuild (a fresh agent follows create-repo and the skills literally: REST + JWT + JPA/Flyway + Kafka
  outbox + metrics + health): BUILD SUCCESS — 154 tests, JaCoCo 85/75 per class, PIT 93 %, Spotless, Checkstyle,
  SpotBugs, Error Prone/NullAway clean, Helm lint strict. It needed 4 workarounds (the previous audit needed 9); all
  are fixed here: `@Nullable` exception causes (+ JSpecify in the ci pom), a transaction manager and Kafka switches for
  component tests with persistence/messaging, Resilience4j-annotated client mocks, a parseable health-indicator test
  URL; ShedLock setup documented. Testcontainers ITs did not run (no Docker).

## [2.2.0] - 2026-11-11

### Added
- **Eval suites** (`evals/<plugin>/`, run with `tools/run-evals.sh`): one trigger case per skill (73), negative cases per
  plugin (unrelated request; other language stack), with/without-plugin behaviour cases for 21 skills, and agent cases
  (one per agent, on a small Spring Boot / FastAPI / React Native fixture). The validator fails when a skill or agent
  has no case. Results are under "Eval results" below.
- **Freshness policy** (`docs/AUTHORING.md` §9): skills are re-reviewed within 180 days; the validator warns after 150
  and fails after 180 or on a future `last_reviewed`.
- README: support status and prerequisites per language (Java: Java 21, Spring Boot 3.5, Maven, **Lombok**), and
  "Defaults you can override". Routing hooks: project `CLAUDE.md` conventions override skill defaults.
- Validator: marketplace and `plugin.json` descriptions must be identical; experimental plugins and skills must carry
  their label.

### Changed
- RFC 7807 → **RFC 9457** (Problem Details) everywhere; the wire format is unchanged.
- Python and React Native are **Experimental** (was "draft"): plugin descriptions start with `Experimental — ` and every
  skill and agent carries the Experimental banner.
- `pr-description` is host-neutral (GitHub, GitLab, Azure DevOps, Bitbucket Cloud/Server); the Bitbucket Server REST
  procedure moved unchanged to `references/bitbucket-server.md`.
- `external-client`: the per-dependency transport is never injectable by type alone — a named bean with `@Qualifier`,
  or no transport bean at all (as the template does).
- `code-structure` declares Lombok as a prerequisite of every Java skill; `ci` documents the `maven-21` Jenkins agent
  label as a placeholder.

### Fixed
- Five plugins had different descriptions in `marketplace.json` and `plugin.json`.

### Eval results (2026-11-11, Claude Code 2.1.311, default model)
- **Routing:** 73/73 trigger cases loaded their skill; 29/29 negative cases (unrelated request, other language stack)
  loaded none — 1 run each.
- **Behaviour**, mean score with plugin vs without (3 runs per arm). Clear lift on 16 of 21:

  | Skill | With | Without | Only with the skill |
  | --- | --- | --- | --- |
  | `permissions` | 1.00 | 0.00 | `PermissionsHandler` + one `PermissionsCheckStrategy` per caller, `ForbiddenException` |
  | `request-metrics` | 1.00 | 0.00 | Filter + `MetricsRecorder`, `MonitoringConstants`, `shouldNotFilter` |
  | `feature-flags` | 1.00 | 0.33 | `FeatureTogglePort`, kebab-case flag names |
  | `strategy-registry-pattern` | 0.80 | 0.20 | `*Registry` over an injected `List<*Strategy>` |
  | `git-commit-conventions` | 1.00 | 0.33 | Conventional Commit subject |
  | `pr-description` | 1.00 | 0.33 | Problem / Solution / Key Changes / Testing |
  | `exception-handling` | 1.00 | 0.40 | typed hierarchy, `ExceptionMessages`, `MessageFormat` |
  | `component-tests` | 1.00 | 0.47 | `ComponentTestConfiguration`, `MessageFormat` URLs, test profile |
  | `external-client` | 1.00 | 0.50 | `<Dep>Properties`, `RestClient.Builder.clone()`, non-2xx mapping |
  | `api-design` | 1.00 | 0.67 | export as a sub-resource |
  | `integration-tests` | 1.00 | 0.75 | `@Tag("integration")` |
  | `input-validation` | 0.80 | 0.60 | Spring `Validator` for the cross-field rule |
  | `persistence` | 1.00 | 0.80 | JPA auditing |
  | `domain-modeling` | 1.00 | 0.80 | identifier value object |
  | `unit-tests` | 1.00 | 0.80 | `methodName_condition_expectedResult` naming |
  | `spring-boot-conventions` | 1.00 | 0.83 | keys in `ConfigurationConstants` |

  No measurable difference — the model already follows the practice: `messaging`, `graceful-shutdown`,
  `resilience-patterns`, `release-versioning`, `documentation-and-adr`.
  Open: `input-validation` put the SKU rule in the injected catalogue bean, not a `*Rule` class (0/3);
  `strategy-registry-pattern` named the interface without `Strategy` in 1 of 3 runs.
- **Agents** (request names the agent, on a small project fixture; 1 run each): 24/24 cases pass — every agent is
  started under its plugin name and loads its key skills; no agent starts for an unrelated question, and
  `scaffold-repo` is never run as a subagent. The first run passed 19/24; every failure was a fixture gap that made the
  agent stop and ask instead of guessing, which is the intended behaviour. Open: `react-native-new-screen` and
  `new-feature` sometimes ask for clarification before loading skills (1 of 2 runs).

### Changed (breaking)
- **Spring Boot pinned to 3.5.x** for all Java skills, templates and `create-repo` (no longer "latest").
- **Domain exceptions are unchecked**: `BaseDomainException extends RuntimeException` with subclasses per HTTP status (400/403/404/406/409/429/503/500) and `ExceptionMessages` in `exception.constants`; `GlobalExceptionHandler` in `exception.handler`. `@Transactional` now rolls back on domain failures.
- Docker image uses `-Djarmode=tools extract --layers --launcher` (layertools is deprecated).

### Fixed
- Generated Java service builds on Spring Boot 3.5 without workarounds: Lombok dependency, permissions/exception templates compile together, `@ConfigurationPropertiesScan`, security test profile, PIT 1.20 + junit5 plugin 1.2.3, Jacoco 85 % line / 75 % branch per class enforced, NullAway excludes generated code.
- Data-loss and security bugs: outbox `event-id` header, idempotent consumer atomicity, retry/Resilience4j AOP, idempotency key, multi-tenancy leak, `?layout=full` authorization, NoOp fallbacks for security ports now fail at startup.
- github-actions-ci workflows are valid YAML; Helm chart gains service/hpa/pdb/serviceAccount/secret templates, a ServiceMonitor CRD guard and documented two-step render; Jenkins adds dependency-check and Trivy scans.
- Agents: code-review loads its skills and stays read-only; HITL questions stay in the main session; new untracked files are reviewed; Java agents name their language; tests are written after the code exists.
- Commit guard: closes the safe-flag bypass (`git commit -m "--abort"`) and guards `git stash`, plumbing, history rewrites, `gh` writes and more publish commands; no-python fallback rewritten. Publish blocklist check works on macOS.
- Routing: authorization row, `ci` vs `github-actions-ci` (never both), monorepo and empty-folder detection; Python detector ignores `docs/requirements.txt`.
- Python and React Native draft examples type-check and pass tests; versions and APIs updated (pytest-asyncio ≥ 0.26, zod 4, TypeScript 6).
- Cross-skill contradictions resolved (config, caching, coverage, packages, test naming, metrics, tracing, release, profiles); docs, setup and validators corrected.

### Fixed
- `cd`: generated charts read the image registry from `global.imageRegistry` when an umbrella chart sets it, falling back to `image.registry`.
- Skill descriptions shortened to at most 300 characters (validator limit lowered from 600) so a full language install fits the skill-listing budget better — Java install from ~23k to ~14k characters.
- `ai-toolkit-python` and `ai-toolkit-react-native` now depend on `ai-toolkit-docs`, which `completion-gate` uses for its docs step.
- Review pass across all plugins:
  - **Build breakers:** Lombok in `annotationProcessorPaths`, `BaseEntity` `@Version` ambiguity, Jenkins image-tag and GitHub Actions cosign digest.
  - **Contradictions between skills:** pattern-selection vs code-structure, component vs integration tests, config and assertion conventions.
  - **Skill text vs templates:** permissions, messaging outbox/idempotent consumer, ci Dockerfile/Jenkinsfile.
  - **Outdated APIs:** `@MockitoBean`, `httpexchanges`, Pact JUnit 5, Flyway 10.
  - **Agents:** use qualified skill names and keep developer-question (HITL) steps out of subagents.
  - **Python / React Native drafts:** broken examples.
- Guild #23: Simple Wrapper / Lite / Full 5-Layer by scale is kept; the dedicated-class and `exchangeToMono` requirements apply to Full 5-Layer only.

### Changed
- Image tags: release `vX.Y.Z` → image `X.Y.Z`, `main` builds → `BUILD_NUMBER` (no `latest`); Helm tag defaults to `.Chart.AppVersion`.
- Unit tests default to AssertJ and one naming convention (`methodName_condition_expectedResult`).

## [2.1.1] - 2026-11-04

### Fixed — review pass
- **Helm / ops:** the HPA target was 500 % CPU and could never scale out (now 80); the deployment template now has the `runAsNonRoot`, read-only root
  filesystem, `/tmp` volume, `terminationGracePeriodSeconds` + `preStop` and startup probe its skills require, and probe periods that detect a hung pod in
  about 30 s instead of 50 minutes; the health-indicator templates now produce valid `@Value` placeholders; request-metrics no longer uses caller-controlled
  tag values, matches URIs inside the context path, cannot replace a handler's result from `finally`, and its tests no longer fail on strict stubs;
  tracing config uses Spring Boot's `management.otlp.tracing.*` keys.
- **Messaging / Kafka:** the consumer example acknowledges after the transaction commits; retry properties use `spring.kafka.retry.topic.*`; the container
  factory customises Boot's instead of replacing it; the outbox relay is property-driven, waits for the broker ack and uses `SKIP LOCKED`.
- **Build skills:** `PermissionsHandler` / `PermissionsCheckStrategy` templates compile and match the skill (plus a `PermissionsRegistry` template);
  `SecurityConfig` is stateless and allows the actuator endpoints the skills expose; `GlobalExceptionHandler` logs, maps `ConstraintViolationException`
  to `400` and lets Spring Security exceptions through; `@Version` is a `Long` (a primitive broke auditing with assigned ids); `@Where` → `@SQLRestriction`;
  external-client applies connect / response timeouts, retries on the translated exception and no longer logs bodies; PII masking is wired and no longer
  leaves the tail of an email; sdk-publishing compiles (public `internal` classes, actuator bean in a conditional nested class); validator messages escape
  request data (template injection); Bucket4j example uses the current API and a bucket per client.
- **Design / quality:** the `Application` template no longer carries `@EnableScheduling`, a bare `@ComponentScan` or `@PropertySource`; the ArchUnit layer
  rule uses layer names; Spring Boot conventions corrected (`@Validated` on properties records, processor dependency, `ConstraintViolationException`
  handling, `@Scheduled` error behaviour, `AFTER_COMMIT` listeners, profiles); async-api-patterns matches api-design and guards webhooks against SSRF;
  PIT config includes `pitest-junit5-plugin`; Error-Prone JDK flags and SpotBugs threshold match the CI policy; integration-test naming / WireMock version
  / `@Transactional` caveat; class-size and coverage numbers agree across skills; Flyway baseline and duplicate-removal steps are safe.
- **Agents:** `new-microservice-client` asks the scale questions and no longer suggests hyphenated Java packages; `code-review` no longer demands five layers
  for a small client; `refactor` records its notes in the report; `new-validation` no longer prescribes an inline `@MockBean`.
- **Docs / tooling:** `prepare-for-publish.sh` no longer fails on itself, handles quotes in the blocklist and case-insensitive path leaks;
  `check-versions.sh` fails on a downgrade, counts new files and fails closed in CI; `check-links.py` checks case-exact paths; `validate-context.sh` handles
  adjacent required sections, multi-line comments and a missing final newline; the commit-guard fallback also covers `npm` / `mvn` release commands;
  the diagram guidance agrees (Mermaid by default); stale tier counts, agent lists, scaffolds, detection markers and the Copilot symlink command are fixed.
- **Dependencies:** the three `-design` plugins depend on `ai-toolkit-quality` (their routing tables cite `completion-gate`); the validator now fails a
  qualified `ai-toolkit-x:skill` reference that its plugin does not depend on.

## [2.1.0] - 2026-11-04

### Changed — plugin dependencies match what skills need
- Install a language with its new meta plugin: `ai-toolkit-java`, `ai-toolkit-python` or `ai-toolkit-react-native`
  (manifest-only; they depend on the language's design, build, quality and ops plugins plus the neutral ones).
  `ai-toolkit-<lang>-design` no longer pulls in its siblings. Existing installs keep what they already have.
- Every plugin now declares the plugins its skills' `depends_on` need, so a phase plugin installed on its own brings
  its prerequisites (for example `ai-toolkit-java-build` also installs design, ops, quality and workflow).
  The graph is acyclic: design → quality → ops → build.
- Four `depends_on` entries that pointed from a design skill back at a build skill (`api-design`, `async-api-patterns`,
  `pattern-selection`, React Native `state-and-data`) are removed; the skills still mention them in prose.
- `validate-skills.sh` fails a cross-plugin `depends_on` that its plugin does not declare, a dependency on an unknown plugin,
  and any dependency cycle.
- Plugin versions: Java phase plugins `1.2.0`, Python / React Native phase plugins `0.2.0`; new meta plugins `1.0.0` (Java) and `0.1.0` (drafts).

## [2.0.0] - 2026-11-04

### Changed — skills load on demand
- The ten largest Java skills (`external-client`, `input-validation`, `request-metrics`, `code-structure`, `unit-tests`,
  `strategy-registry-pattern`, `pattern-selection`, `testable-code-principles`, `quality-review`, `pluggable-architecture`)
  keep decision gates, layout, Do / Don't and a reference map in `SKILL.md`. The code-heavy sections moved verbatim to
  `references/` and are read only when needed: each `SKILL.md` is 45–83 % smaller, about 112 KB less across the ten.
  Section numbers and headings are unchanged, so `skill §N` citations still resolve.
- `pattern-selection` is generated as a lean `SKILL.md` plus `references/` from `docs/PATTERN_SELECTION_GUIDE.md`
  (`tools/build-indexes.py --check` covers the references).
- `docs/AUTHORING.md` §3b documents the `references/` convention.
- Python and React Native plugins are versioned `0.1.0` to match their draft status; all other plugins are `1.1.0`.
- CI actions are pinned by commit SHA and `base_ref` is passed through `env:`.

### Added
- `validate-skills.sh` now fails on a `SKILL.md` over 16 KB, on a review agent that is not read-only, and on a
  `` `skill` §N `` citation that has no matching heading.
- `plugin.json` metadata on every plugin: `license`, `repository`, `homepage`, `keywords`.

### Fixed
- Commit guard: `git commit -n` (`--no-verify`) and `git merge -n` / `git rebase -n` no longer skip the prompt; `-n` is
  treated as a dry run only for `git push`.
- Commit guard: `gh api` writes now ask — `--method=POST`, `-XPOST`, and bodies sent with `-f` / `-F` / `--field` / `--input`.
- Commit guard: the no-python fallback also asks for `am`, `revert`, `reset --hard`, `gh pr create|merge` and `gh release create`.
- Two citations that pointed at sections that do not exist (a `quality-review` item and a `code-structure` subsection), and a single logging annotation (`@Slf4j`).
- `external-client` no longer prescribes an inline `@MockBean`; `component-tests` notes the Spring Boot 3.4 deprecation
  in favour of `@MockitoBean`; the `ci` example uses `{{springBootVersion}}` instead of a pinned 3.3.4.
- `docs/REGISTRY.md` totals list the real tiers (MUST / SHOULD / MAY / FOUNDATIONAL) instead of a single "Public" row.


### Changed — marketplace restructure (breaking: plugin and path names)
- The catalogue is now a Claude Code **plugin marketplace** (`.claude-plugin/marketplace.json`,
  `plugins/ai-toolkit-<phase | lang-phase>/`). Skills, agents, context templates, tools and docs
  moved from `copilot/public/...` to `plugins/*/skills/`, `plugins/*/agents/`, `tools/` and `docs/`.
  All 47 original skills, their templates and the 10 original agents are preserved; edits to them are
  limited to sharper `description:` triggers, cross-plugin links rewritten as skill names, and (in the
  language-neutral skills) additional non-Java examples next to the original Java ones.
- Plugins are split by **delivery phase** and **language**: neutral `workflow`, `docs`, `quality`;
  Java `design`/`build`/`quality`/`ops`/`scaffold`/`agents`; Python and React Native drafts.
  See `LANGUAGE_CONTRACT.md`.
- `update-context` agent is now language-neutral and lives in `ai-toolkit-docs`.
- The GitHub Copilot / JetBrains setup is kept (`setup/jetbrains/`), with paths updated.

### Added — multi-language and definition of done
- Routing hooks that inject a task → skill table per detected language, and a hook that asks before
  any `git commit` / `git push`.
- Skills: `parallel-delegation`, `completion-gate`, `code-hygiene`, `sonar-quality-gate`.
- Skills `golden-path` (apply-order + the 24 non-negotiables) and `pattern-selection` (smallest pattern that fits), generated from
  `docs/BACKEND_GUILD.md` and `docs/PATTERN_SELECTION_GUIDE.md` so installed agents can load them.
- `tools/test-hooks.sh` — behavioural tests for the commit guard (a command parser, not a text match) and the language detectors.
- Agents: `test-writer` and delegation / commit-policy / completion-gate sections in the code-writing agents.
- Python (10 skills, 5 agents) and React Native (10 skills, 5 agents) drafts.
- `tools/check-links.py`, `docs/LANGUAGE_CONTRACT.md`, language-contract and marketplace checks in `validate-skills.sh`.
- Plugin icons, plugin `dependencies`, `.gitattributes`, a CI workflow and pre-commit config, and a release gate for maintainers.
- A session-start warning and `scripts/remove-old-copies.sh` for stale user-level copies that shadow the plugins.

### Fixed
- Descriptions of 19 skills now say when to use them and which sibling to use instead.

### Added
- `agents/scaffold-repo.md` — new HITL agent for creating a brand-new Spring Boot
  service repository from scratch (wraps `project-types`, `create-repo`, `code-structure`,
  `ci`, `cd`, `local-dev-experience`, and baseline non-negotiables).
- `agents/new-kafka-consumer.md` — focused agent for adding a Kafka consumer with
  idempotency, DLQ, outbox, observability, and graceful-shutdown wiring.
- `agents/refactor.md` — incremental refactoring agent that maps anti-patterns to
  canonical skills and enforces characterisation tests before each migration step.
- `CHEATSHEET.md` — pro tips for working inside this repo using IntelliJ IDEA and
  the CLI: daily commands, navigation shortcuts, skill scaffolding, pre-commit alias,
  dependency graph reference, and three-rule test for new skills.
- **Co-located every tool next to what it serves** (the `context/` folder was
  already the model, with its own `validate-context.sh`):
  - Skills tooling + docs now live inside `public/skills/`: `REGISTRY.md`,
    `AUTHORING.md`, `INDEX_BY_USE_CASE.md`, `BACKEND_GUILD.md`, `build-indexes.py`,
    `validate-skills.sh`, and a skills-focused `CHEATSHEET.md`.
  - `AGENT_PROMPT.md` moved next to the agents in `public/agents/`, with a new
    agents-focused `public/agents/CHEATSHEET.md`.
  - The `copilot/` root now holds only the global view: `README.md`, `HOW-TO.md`,
    a high-level `CHEATSHEET.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `LICENSE`.
  - `build-indexes.py` and `validate-skills.sh` rewritten to treat `public/skills/`
    as their own directory (skills are now direct children; generated links are
    `./<name>/SKILL.md`).
  - Updated every cross-reference across all docs, agents, and `setup/jetbrains/*`;
    fixed two pre-existing broken cross-skill links surfaced by the move. Verified
    zero broken relative links; all validators pass.

### Changed
- **Restructured the catalogue under a `public/` folder.** Skills now live at
  `public/skills/<name>/SKILL.md` and agents at `public/agents/<name>.md`, so
  skills and agents have their own folders. The
  shared meta + tooling files (`REGISTRY.md`, `AGENT_PROMPT.md`, `BACKEND_GUILD.md`,
  `INDEX_BY_USE_CASE.md`, `AUTHORING.md`, `build-indexes.py`, `validate-skills.sh`)
  now sit at the `copilot/` root.
  - `build-indexes.py` — discovery glob and generated links updated to `public/skills/`.
  - `validate-skills.sh` — rewritten for the fixed `public/skills/` layout; index
    check targets `public/skills/README.md`.
  - Folded the old `skills/README.md` intro into `public/skills/README.md`.
  - Updated every cross-reference across the docs, all 10 agent files, and
    `setup/jetbrains/*`. Verified zero broken relative links; all validators pass.
- **Moved `skills/agents/` → `public/agents/`** — agents are compositions that orchestrate
  skills, not a kind of skill, so they live alongside `public/skills/` under `public/`.
- `copilot/README.md` — added a `public/agents/` row to "What's inside" and retitled to
  "Skills, Agents & Context Platform".
- `HOW-TO.md` — Option B agent list expanded from 7 to all 10 agents.
- `agents/README.md` — updated index table from 7 to 10 agents.
- `HOW-TO.md §5` — task-recipe table updated: `scaffold-repo`, `new-kafka-consumer`,
  and `refactor` now point to their dedicated agents instead of `AGENT_PROMPT.md`.
- `HOW-TO.md` quick-navigation table — added `CHEATSHEET.md` entry at the top.
- `setup/jetbrains/cheatsheet.md` — agents table and usage examples updated to
  cover all 10 agents.
- Root `README.md` — agent count updated from 7 to 10; added a `setup/` row to
  the "What's inside" table.

### Fixed
- `setup/jetbrains/cheatsheet.md` — replaced a stale `./bin/install-global.sh`
  reference (the `bin/` scripts were removed) with the direct `ln -s` command.
- `setup/jetbrains/README.md` — corrected the "7 task agents" label in the
  how-it-works diagram to 10.
- `README.md` — corrected the "7 task agents" count in the "What's inside" table to 10.

## [1.0.0] - 2026-07-07

### Added
- `setup/jetbrains/` — JetBrains + GitHub Copilot setup guide, with:
  - `README.md` — three-step setup walkthrough (symlink → global instructions → use).
  - `copilot-global-instructions.md` — exact 2-line snippet to paste into
    JetBrains → Settings → Tools → GitHub Copilot → Custom Instructions.
  - `cheatsheet.md` — ready-to-paste `#file` chat patterns for all 40 skills,
    7 task agents, and common full-task recipes (new endpoint, Kafka consumer, etc.).

### Changed
- `HOW-TO.md` §2 rewritten: leads with the symlink/zero-token approach before
  the context-docs copy step.
- Root `README.md` Quick-start section updated to lead with the global JetBrains
  setup path and reference the new `setup/jetbrains/` guide.

### Changed
- `validate-skills.sh` is now tier-agnostic: discovers any one-level subfolder under `skills/` rather than hard-coding tier names.

### Added
- Created `context/` documentation folder with placeholder templates (project overview, architecture, code standards, build plan, library docs, progress tracker, system context, component diagram, flow diagram).
- Created `context-maintenance` and `uml-diagram` skills.
- Added this CHANGELOG.md following the Keep a Changelog format.
- Expanded `skills/public/ci/SKILL.md` from a 20-line stub to a full skill (concrete `pom.xml`, multi-stage `Dockerfile`, declarative `Jenkinsfile`, wiring matrix, do/don't).
- `skills/AGENT_PROMPT.md`: Operator manual for code-generating agents to use the catalogue autonomously.
- `skills/build-indexes.py`: Automation to keep `REGISTRY.md` and `BACKEND_GUILD.md` in sync with frontmatter.
- `skills/INDEX_BY_USE_CASE.md`: Reverse-lookup table for developer tasks.
- 30+ new templates across `code-structure`, `exception-handling`, `external-client`, `persistence`, and `messaging`.
- Context infrastructure: `glossary.md`, `runbooks.md`, `slo.md`, `dependencies.md` templates and `context/validate-context.sh`.
- Governance: `LICENSE` (MIT), `CONTRIBUTING.md`, and `.editorconfig`.

### Fixed
- Validator no longer fails on a missing tier README — the second tier has been removed entirely.
- Resolved previously-broken links in `skills/public/README.md` to `REGISTRY.md` and `AUTHORING.md` (files referenced but missing — both now exist).
- Corrected `skills/public/README.md` `uml-diagram` row (was "PlantUML", is "Mermaid").

## [0.3.0] - 2026-06-30

### Added
- `pluggable-architecture` skill (MUST tier) — Ports & Adapters policy for every external
  technology integration, config-driven selection/composition, ArchUnit enforcement.
- `adapter-contract-tests` skill (SHOULD tier) — TCK-style shared abstract test suites
  proving every adapter is interchangeable; composite-adapter failure isolation tests.
- 2 new non-negotiables (20 and 21) added to `BACKEND_GUILD.md` for port isolation and
  adapter TCK coverage, bringing the total to 24.
- New task recipe §3.9 in `BACKEND_GUILD.md`: "New external technology integration".
- New use-case row in `INDEX_BY_USE_CASE.md`: "Integrate a swappable technology".
- `pluggable-architecture` wired as a `depends_on` prerequisite for `observability`,
  `persistence`, `messaging`, `external-client`, `rate-limiting`, `data-privacy`, and
  `feature-flags` to enforce apply-order in the dependency graph.

### Changed
- `REGISTRY.md` and `BACKEND_GUILD.md` regenerated via `build-indexes.py`; skill count
  updated to 38.

## [0.2.0] - 2026-07-05

### Added
- `HOW-TO.md` — 10-section developer and agent guide (quick navigation, agent setup,
  bootstrapping, tier explanations, three architectural laws, task recipes, dependency
  map, glossary, FAQ).
- `skills/agents/` — 7 topic-specific AI agent prompts: `new-endpoint`, `new-feature`,
  `new-microservice-client`, `new-validation`, `new-metric`, `code-review`,
  `update-context`.
- `skills/agents/README.md` — index table for all topic agents.

## [0.1.0] - 2026-06-28

### Added
- Initial public release of the skills catalogue with 36 atomic, vendor-neutral skills.
- `skills/AGENT_PROMPT.md` — operating manual for code-generating agents.
- `skills/BACKEND_GUILD.md` — MUST/SHOULD/MAY adoption matrix, apply-order, 19 non-negotiables.
- `skills/REGISTRY.md` — machine-readable index auto-generated from frontmatter.
- `skills/INDEX_BY_USE_CASE.md` — reverse-lookup from developer task to skill set.
- `skills/AUTHORING.md` — authoring contract and validation guide for new skills.
- `skills/build-indexes.py` — automation to regenerate REGISTRY and BACKEND_GUILD matrix.
- `skills/validate-skills.sh` — structural linter for all SKILL.md frontmatter.
- `context/` — documentation template folder (architecture, SLOs, runbooks, glossary, etc.).
- `context/validate-context.sh` — validator ensuring required context sections are populated.

---

## Changelog Guidelines

### Entry Format
When adding entries, use this format:

```markdown
## [Version] - YYYY-MM-DD

### Added
- New features

### Changed
- Changes to existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Removed features

### Fixed
- Bug fixes

### Security
- Security fixes
```

### Categories

- **Added**: New features
- **Changed**: Changes in existing functionality
- **Deprecated**: Soon-to-be removed features
- **Removed**: Now-removed features
- **Fixed**: Any bug fixes
- **Security**: Vulnerability fixes

### Best Practices

1. **Append only**: only add new entries at the top (under `[Unreleased]`).
2. **User-focused**: write from the user's perspective.
3. **Group similar changes**: keep related changes together.
4. **Link issues**: reference tracker tickets or pull requests when applicable.
5. **Be specific**: provide enough detail to understand the change.
6. **Release date**: add the date when moving `[Unreleased]` to a version number.

### Example Entry

```markdown
## [1.0.0] - 2026-07-15

### Added
- Async processing support for large payloads (#PROJ-123).
- Redis caching layer for frequently accessed resources.
- Prometheus metrics export endpoint.

### Changed
- Increased default request timeout from 30s to 60s.
- Updated Spring Boot from 3.1.0 to 3.2.0.

### Fixed
- Memory leak in long-running sessions (#PROJ-456).
- Null-pointer exception when an optional field is missing.
```

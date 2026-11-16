# ai-toolkit

A Claude Code **plugin marketplace** of engineering standards, organised by **delivery phase**
and **language**: skills, task agents and routing hooks that make sure the standards are loaded
before code is written.

## Install

```
/plugin marketplace add oriddd/ai-toolkit
/plugin install ai-toolkit-java@ai-toolkit               # your language: java | python | react-native
/plugin install ai-toolkit-java-agents@ai-toolkit        # optional: task agents
```

Installing a language's plugin (`ai-toolkit-java`, `-python`, `-react-native`) pulls in its design, build, quality and ops plugins plus the neutral
`workflow`, `quality` and `docs` plugins through plugin dependencies. A single phase plugin installs on its own too and brings only what its skills depend on. A language's routing table is injected only when the project
is that language (detected from `pom.xml`, `pyproject.toml`, `package.json` with react-native, …). **Install only the
languages you use** — every installed skill adds its description to each session. Details, team-wide setup, updates,
Windows notes and the commit-guard limits: [`setup/claude-code/README.md`](./setup/claude-code/README.md).

| Phase | Neutral | Java | Python (experimental) | React Native (experimental) |
| --- | --- | --- | --- | --- |
| Workflow — commits, PRs, releases, delegation | `ai-toolkit-workflow` | | | |
| Docs — ADRs, diagrams, context | `ai-toolkit-docs` | | | |
| Quality gate — definition of done, hygiene, Sonar | `ai-toolkit-quality` | | | |
| Design — structure, patterns, conventions | | `-java-design` | `-python-design` | `-react-native-design` |
| Build — errors, validation, persistence, security | | `-java-build` | `-python-build` | `-react-native-build` |
| Quality — tests, static analysis, review | | `-java-quality` | `-python-quality` | `-react-native-quality` |
| Ops — CI/CD, observability | | `-java-ops` | `-python-ops` | `-react-native-ops` |
| Scaffold | | `-java-scaffold` | | |
| Task agents | `update-context` (in `-docs`) | `-java-agents` | `-python-agents` | `-react-native-agents` |

## Support status and prerequisites

| Language | Status | Prerequisites |
| --- | --- | --- |
| Java | **Supported** — the user-tested core of the catalogue; trigger-tested by the eval suites in [`evals/`](./evals) | Java 21, Spring Boot 3.5 (Jakarta EE 10), Maven, **Lombok** (`org.projectlombok:lombok`, `<optional>true</optional>`, version from the Boot parent) |
| Python | **Experimental** — required concerns only, not yet validated on production projects | Python 3.14 (3.12+ supported), FastAPI, uv |
| React Native | **Experimental** — required concerns only, not yet validated on production projects | React Native with TypeScript, Expo (EAS) or bare workflow (Fastlane), npm |

The Java skills' examples and templates use Lombok (`@Slf4j`, `@RequiredArgsConstructor`, `@Builder`, …). The
`create-repo` and `ci` POM templates already include it; add it to an existing project before applying the skills.

**Spring Boot 3.5 is the default, tested baseline; Boot 4.1 is a verified second target.** `create-repo` generates 3.5 and
accepts 4.x as a supported variant. A service rendered from the `ci` POM (Error Prone + NullAway at ERROR, JDK 21) with the
exception-handling, permissions, `external-client` HTTP adapter, persistence (`BaseEntity`, auditing, outbox entity on Postgres),
messaging (compile only), request-metrics, graceful-shutdown, component-test and `ArchitectureTest` templates was built on 3.5.16
and on 4.1.2 and passed the same 26 tests on both. A few edits are dual-compatible and already in the templates; the rest
differ on 4.x (Jackson 3, modular starters, renamed packages and auto-configuration classes, Hibernate 7 `hibernate-processor`,
Testcontainers 2, `TestRestTemplate` module): see
[`spring-boot-4.md`](./plugins/ai-toolkit-java-design/skills/spring-boot-conventions/references/spring-boot-4.md). Not verified
on 4.x: Flyway on Postgres, outbound OAuth2 client, springdoc, openapi-generator, Resilience4j, Bucket4j, ShedLock, Kafka retry/DLT
against a broker, the JPA metamodel generation, and the Spotless/SpotBugs/JaCoCo/PIT gates. **Open-source support for 3.5 ended on 2026-06-30**
([support window](https://spring.io/projects/spring-boot#support)): new 3.5 patches need commercial support, so plan the
Boot 4 move; `create-repo` says so when it asks for the Boot version.
Every skill carries a `last_reviewed` date and is re-reviewed on a fixed cadence — see
[`docs/AUTHORING.md` §9](./docs/AUTHORING.md#9-freshness-policy).

## Defaults you can override

The skills are **opinionated defaults**, not universal law: one exception-message catalogue, `MessageFormat`
placeholders, the `<basePackage>` layout, Strategy + Registry for runtime variation, and so on. They are written as
firm rules so that an agent produces one consistent style instead of a mix. When your team has a different
convention, state it in the project's `CLAUDE.md` (or `context/code-standards.md`): project instructions take
precedence over a skill, and the agents follow the project's existing style when it conflicts with a skill's default.

All plugin names are prefixed `ai-toolkit`. How the axes and the per-language skill contract work:
[`docs/LANGUAGE_CONTRACT.md`](./docs/LANGUAGE_CONTRACT.md). Other agents (Cursor, Copilot, …) can read the `SKILL.md` files directly.

**Never commits on its own** (by instruction, backed by a best-effort hook): agents leave changes in the working tree until you ask, and finish with the
`completion-gate` evidence table (build, tests, static analysis, standards review, coverage, hygiene, Sonar).

## GitHub Copilot / JetBrains

Prefer Copilot? Symlink the repo (`ln -sfn /path/to/ai-toolkit ~/.ai-toolkit`), paste
[`setup/jetbrains/copilot-global-instructions.md`](./setup/jetbrains/copilot-global-instructions.md) into
JetBrains → Settings → Tools → GitHub Copilot → Custom Instructions, and load skills on demand:

```
#file ~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/exception-handling/SKILL.md
Apply this skill to the current file.
```

Full guide: [`setup/jetbrains/README.md`](./setup/jetbrains/README.md) · ready-to-paste patterns:
[`setup/jetbrains/cheatsheet.md`](./setup/jetbrains/cheatsheet.md).

## Layout

```
.claude-plugin/marketplace.json
plugins/ai-toolkit-<phase | lang-phase>/{.claude-plugin/plugin.json, skills/, agents/, hooks/}
docs/    indexes, BACKEND_GUILD (non-negotiables), guides
evals/   claude plugin eval suites per plugin (tools/run-evals.sh)
tools/   validate-skills.sh, build-indexes.py, check-links.py, test-hooks.sh, check-repo-hygiene.sh, check-versions.sh
setup/   client setup notes
```

## Where to start

- Find a skill for your task: [`docs/INDEX_BY_USE_CASE.md`](./docs/INDEX_BY_USE_CASE.md)
- Mandatory rules (Java / Spring Boot): [`docs/BACKEND_GUILD.md`](./docs/BACKEND_GUILD.md)
- Full guide: [`docs/HOW-TO.md`](./docs/HOW-TO.md)
- Bootstrap a project's docs: copy the [context templates](./plugins/ai-toolkit-docs/skills/context-maintenance/templates/context)

## Contributing

See [`docs/CONTRIBUTING.md`](./docs/CONTRIBUTING.md) and [`docs/AUTHORING.md`](./docs/AUTHORING.md). Before a PR:

```bash
bash tools/validate-skills.sh && python3 tools/build-indexes.py --check && python3 tools/build-evals.py --check \
  && python3 tools/check-links.py && bash tools/test-hooks.sh && bash tools/check-repo-hygiene.sh && bash tools/check-versions.sh
# maintainers, before a release: bash prepare-for-publish.sh   (confidential-term checks need a local .publication-blocklist)
# or run it on every push: pip install pre-commit && pre-commit install --hook-type pre-commit --hook-type pre-push
```

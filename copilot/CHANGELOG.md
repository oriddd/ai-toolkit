# Changelog

All notable changes to this catalogue will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
    `./<name>/SKILL.md`); the optional `.publication-blocklist` now lives in
    `public/skills/`.
  - Updated every cross-reference across all docs, agents, and `setup/jetbrains/*`;
    fixed two pre-existing broken cross-skill links surfaced by the move. Verified
    zero broken relative links; all validators pass.

### Changed
- **Restructured the catalogue under a `public/` folder.** Skills now live at
  `public/skills/<name>/SKILL.md` and agents at `public/agents/<name>.md`, so a
  future `private/` fork can mirror the same `skills/` + `agents/` split. The
  shared meta + tooling files (`REGISTRY.md`, `AGENT_PROMPT.md`, `BACKEND_GUILD.md`,
  `INDEX_BY_USE_CASE.md`, `AUTHORING.md`, `build-indexes.py`, `validate-skills.sh`)
  now sit at the `copilot/` root.
  - `build-indexes.py` — discovery glob and generated links updated to `public/skills/`.
  - `validate-skills.sh` — rewritten for the fixed `public/skills/` layout; index
    check targets `public/skills/README.md`; blocklist reads `.publication-blocklist`
    at the `copilot/` root and scans `public/**`.
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
- Collapsed the skills catalogue from a two-tier layout (vendor-neutral + organization-specific overlays) into a single vendor-neutral tier. The organization-specific overlay directory and its associated `CODEOWNERS` file have been deleted.
- Removed the hard-coded organization-term blocklist from `validate-skills.sh`. Publication-safety checking is now opt-in via an optional, uncommitted `skills/.publication-blocklist` file.

### Changed
- Rewrote `skills/README.md`, `skills/REGISTRY.md`, `skills/AUTHORING.md`, and `skills/public/README.md` to remove every reference to internal tier names, internal mirrors, organization brand names, and private group names.
- `skills/BACKEND_GUILD.md` — dropped the organization-overlay row from the MAY tier, the overlay annotation in the apply-order diagram, and the broken `CODEOWNERS` link.
- Two skills (`exception-handling`, `ci`) — replaced "internal overlay" phrasing with "private wrapper in your fork".
- `skills/public/create-repo/SKILL.md` — renamed a prompt variable that was suggestive of a private BOM artifact to `springBootVersion`.
- `validate-skills.sh` is now tier-agnostic: discovers any one-level subfolder under `skills/` rather than hard-coding tier names.

### Added
- Optional `skills/.publication-blocklist` mechanism — orgs that maintain private forks can list substrings the validator must reject anywhere under `skills/**/*.md`. Absent by default; check is a no-op without the file.
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
- Removed a leaked fully-qualified package path from `skills/public/health-indicator/SKILL.md` (now uses a `{{basePackagePath}}` placeholder).
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

### Fixed
- Replaced project-specific example metric-name constants in `request-metrics/SKILL.md`
  with vendor-neutral `myservice.*` examples.

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

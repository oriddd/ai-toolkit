# Changelog

All notable changes to this catalogue will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed
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

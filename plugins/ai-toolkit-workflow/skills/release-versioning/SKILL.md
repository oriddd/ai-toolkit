---
name: release-versioning
description: >
  Release lifecycle — Conventional Commits, Semantic Versioning, automated CHANGELOG (release-please or
  semantic-release), git tag = artifact version, deprecation policy. Use when releasing a service or library or
  setting up its versioning.
tier: must
applies_to: [rest, event, scheduler, library, monolith, worker, cli, mobile]
depends_on: [git-commit-conventions]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Release & Versioning Skill
A predictable release contract — for humans reading the CHANGELOG and for
machines wiring up the image tag.

## 1. Conventional Commits

Every commit message:

```
<type>(<scope>)!: <summary>

<body>

<footer>
```

| `<type>` | Effect on version |
| --- | --- |
| `feat`    | Minor bump |
| `fix`     | Patch bump |
| `refactor` / `style` / `docs` / `chore` / `test` / `build` / `ci` | No bump |
| `perf` | Patch bump (the default rules of both release-please and semantic-release) |
| `feat!` or `BREAKING CHANGE:` footer | **Major** bump |

Enforced by `commitlint` (npm) in pre-commit / CI:

```yaml
# .github/workflows/lint-commits.yml
- uses: wagoid/commitlint-github-action@v6
```

## 2. Semantic Versioning

`MAJOR.MINOR.PATCH`.

- **MAJOR** — backwards-incompatible change to the public contract (API,
  CLI, library signature, wire format).
- **MINOR** — backwards-compatible feature.
- **PATCH** — backwards-compatible bug fix.

Pre-1.0 is allowed for new services / libraries; treat `0.x` minor as
potentially breaking.

## 3. Automated CHANGELOG + version bump

Pick **one** of:

### a) `release-please` (recommended for polyglot orgs)

Run a `release-please` GitHub Action on `main`. It opens a release PR that
bumps the version in the project's version file (`pom.xml`, `pyproject.toml`, `package.json`, …), regenerates `CHANGELOG.md`, and creates a
git tag on merge.

```yaml
# .github/workflows/release-please.yml
on: { push: { branches: [main] } }
permissions: { contents: write, pull-requests: write }
jobs:
  rp:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with: { release-type: maven, package-name: my-service }   # python | node | simple for other stacks
```

### b) `semantic-release`

`semantic-release` runs at the end of CI on `main`, computes the version
from commits, writes a tag, and publishes. Requires more JS-tooling but is
flexible across ecosystems.

Whichever you pick, the **git tag is the release's source of truth**; the version file is rewritten by the bot to match it, never edited by hand.

## 4. Version-file policy

| Ecosystem | Version file | Working version |
| --- | --- | --- |
| Maven | `pom.xml` | `1.0.0-SNAPSHOT` |
| Python | `pyproject.toml` | `1.0.0.dev0` or the last release |
| Node / React Native | `package.json` (+ native build numbers) | last release |

- On release, the bot rewrites to `1.0.0`, tags `v1.0.0`, and moves to the next development version
  (Maven: bumps the next `-SNAPSHOT`; the working branch is `1.0.0-SNAPSHOT` or whatever the next release will be).
- Never **manually** edit the version in the version file (for Maven: never edit it in `pom.xml`).

## 5. CHANGELOG.md

Conventionally generated when a release bot is configured — then do not hand-edit released sections. Without a bot,
hand-edit only `[Unreleased]` (one bullet per user-visible change) and let the release step rename it. Sections per release:

```
## [1.4.0] — 2026-06-24
### Features
- foo: support PDF/A export (#412)
### Bug Fixes
- foo: handle empty file id (#418)
### Deprecations
- `legacyConvert` endpoint — removed in 2.0
```

## 6. Image tag = version

The `ci` skill's image build uses `${BUILD_NUMBER}` for snapshots and the
git tag (`v1.4.0` → image tag `1.4.0`) for releases. Helm `Chart.appVersion`
mirrors the same value.

## 7. Deprecation policy

- Mark with the language's deprecation marker (`@Deprecated(forRemoval = true, since = "1.4.0")`,
  `warnings.warn(..., DeprecationWarning)`, `@deprecated` TSDoc) and with `Deprecation` + `Sunset`
  headers on HTTP endpoints.
- Remove only in the next **MAJOR** release (removing an API is a breaking change, §2), and not before at least **2 minor releases**
  after the deprecation — longer for public APIs.
- CHANGELOG documents every deprecation under `### Deprecations`.

## 8. Branch model

Default: **trunk-based**. Short-lived feature branches → PR → merge to
`main`. Release tags from `main`.

Hotfixes for older majors live on `release/1.x` branches, cherry-picked
into `main` if relevant.

## Do / Don't

✅ The git tag is the release's source of truth; the version file follows it.
✅ One bot generates the CHANGELOG (or, with no bot, only `[Unreleased]` is hand-edited); humans review.
✅ Conventional Commits enforced by CI, not by reviewer goodwill.
❌ Never tag the same SHA twice with different versions.
❌ Never publish a `1.x.y` after a `2.0.0` exists without explicit hotfix
process (and an entry in CHANGELOG).
❌ Never edit released sections of `CHANGELOG.md` by hand, and never hand-edit it at all when a bot owns it.


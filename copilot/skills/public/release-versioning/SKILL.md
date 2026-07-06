---
name: release-versioning
description: Standardize the release lifecycle — Conventional Commits, Semantic Versioning, automated CHANGELOG generation (release-please or semantic-release), git tag = artifact version, deprecation policy. Use for both deployable services (image tag = version) and libraries (Maven artifact version), tying directly into the `ci` and `sdk-publishing` skills.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: [ci]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Release & Versioning Skill (public)

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
| `perf` / `refactor` / `style` / `docs` / `chore` / `test` / `build` / `ci` | No bump |
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
bumps the version in `pom.xml`, regenerates `CHANGELOG.md`, and creates a
git tag on merge.

```yaml
# .github/workflows/release-please.yml
on: { push: { branches: [main] } }
jobs:
  rp:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with: { release-type: maven, package-name: my-service }
```

### b) `semantic-release`

`semantic-release` runs at the end of CI on `main`, computes the version
from commits, writes a tag, and publishes. Requires more JS-tooling but is
flexible across ecosystems.

Whichever you pick, **only one** version source of truth: the git tag.

## 4. `pom.xml` version policy

- Working branch is `1.0.0-SNAPSHOT` (or whatever the next release will be).
- On release, the bot rewrites to `1.0.0`, tags `v1.0.0`, and bumps the
  next `-SNAPSHOT`.
- Never **manually** edit the version in `pom.xml`.

## 5. CHANGELOG.md

Conventionally generated; do not hand-edit. Sections per release:

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

- Mark with `@Deprecated(forRemoval = true, since = "1.4.0")` on Java APIs;
  with `Deprecation` + `Sunset` headers on HTTP endpoints (see `api-design`).
- Remove after **2 minor releases** (or longer for public APIs).
- CHANGELOG documents every deprecation under `### Deprecations`.

## 8. Branch model

Default: **trunk-based**. Short-lived feature branches → PR → merge to
`main`. Release tags from `main`.

Hotfixes for older majors live on `release/1.x` branches, cherry-picked
into `main` if relevant.

## Do / Don't

✅ One source of truth for the version: the git tag.
✅ One bot generates the CHANGELOG; humans review.
✅ Conventional Commits enforced by CI, not by reviewer goodwill.
❌ Never tag the same SHA twice with different versions.
❌ Never publish a `1.x.y` after a `2.0.0` exists without explicit hotfix
process (and an entry in CHANGELOG).
❌ Never edit `CHANGELOG.md` by hand — the bot owns it.


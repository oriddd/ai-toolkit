---
name: react-native-ci
description: >
  React Native CI/CD on GitHub Actions — cached installs, lint/type/test gates, EAS Build or Fastlane, versioning and
  build numbers, OTA update stance. Use when bootstrapping a pipeline, adding a release path, or changing build or
  versioning.
tier: must
applies_to: [mobile]
depends_on: [react-native-static-analysis, react-native-unit-tests]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

# React Native CI Skill
## When to use

Use when creating or changing the pipeline: PR checks, preview builds, store releases, versioning.
Pick **one** build path per repo: EAS Build (managed, fewer moving parts) or Fastlane on your own
runners (full native control). Default to EAS unless you need custom native build steps.

## Layout

```
.github/workflows/
├── pr.yml            # verify gates on every pull request
├── preview.yml       # EAS preview build on labelled PRs
├── e2e.yml           # Maestro critical flows (nightly and on demand, not a PR gate), see react-native-e2e-tests
├── audit.yml         # scheduled, advisory dependency audit
└── release.yml       # tag-driven store build and submit
.nvmrc                # the Node major CI and developers use (setup-node reads it)
eas.json              # build profiles (EAS path)
fastlane/Fastfile     # lanes (Fastlane path)
```

## Dependencies

```json
{ "devDependencies": { "eas-cli": "<current>" } }
```

`<current>`: pin the latest stable `eas-cli` as an exact version (no `^`), and use the same value for `eas-version` below.

## 1. PR gates (required checks)

```yaml
# .github/workflows/pr.yml
name: pr
on: { pull_request: { branches: [main] } } # `main` = your repository's default branch name; change it if yours differs
concurrency:
  group: pr-${{ github.ref }}
  cancel-in-progress: true
permissions: { contents: read }
jobs:
  verify:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with: { node-version-file: .nvmrc, cache: npm }
      - run: npm ci
      - run: npm run verify
```

`npm run verify` is the verify script from `react-native-static-analysis`: `tsc --noEmit && eslint . --max-warnings 0 && prettier --check . && jest --ci --coverage`.
Mark the `verify` job as a required status check in branch protection. CI runs exactly what developers and agents run
locally; no step is `continue-on-error`. Split it into separate steps (`typecheck`, `lint`, `format:check`, `test`) only
if you want per-step timings in the log.

Dependency audit is **not** a PR gate: `npm audit` results change with the advisory database, so a PR can fail for a
vulnerability it did not introduce. Run it on a schedule and review the result:

```yaml
# .github/workflows/audit.yml
name: audit
on: { schedule: [{ cron: '0 6 * * 1' }], workflow_dispatch: {} }
permissions: { contents: read }
jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with: { node-version-file: .nvmrc, cache: npm }
      - run: npm ci --ignore-scripts
      - run: npm audit --omit=dev --audit-level=high   # advisory: not a required check; triage failures weekly
```

Pair it with automated dependency-update PRs (Renovate or Dependabot) so fixes arrive through the normal `verify` gate.

Optional Sonar stage (only if your organisation runs SonarQube/SonarCloud): reuse the `coverage/lcov.info` that
`jest --ci --coverage` already wrote in the `verify` job, and set `sonar.javascript.lcov.reportPaths=coverage/lcov.info` in
`sonar-project.properties`. Run the scanner after `verify` in the same job and pass the token only through the
environment (`env: { SONAR_TOKEN: '${{ secrets.SONAR_TOKEN }}' }`); never put it in `sonar-project.properties`, a command-line
flag or the repo. Pin the scanner (CLI or vendor action) to a reviewed version.

## 2. Preview builds (EAS)

```yaml
# .github/workflows/preview.yml
name: preview
on: { pull_request: { types: [labeled] } }
permissions: { contents: read }      # eas build needs no write access to the repo
jobs:
  build:
    if: github.event.label.name == 'preview'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with: { node-version-file: .nvmrc, cache: npm }
      - uses: expo/expo-github-action@v8
        with: { eas-version: <current>, token: '${{ secrets.EXPO_TOKEN }}' }   # equals the eas-cli pin in package.json
      - run: npm ci
      - run: eas build --profile preview --platform all --non-interactive --no-wait
```

```json
// eas.json
{ "cli": { "appVersionSource": "remote" },
  "build": {
    "preview": { "distribution": "internal", "channel": "preview" },
    "e2e": { "distribution": "internal", "ios": { "simulator": true }, "android": { "buildType": "apk" } },
    "production": { "autoIncrement": true, "channel": "production" } },
  "submit": { "production": {} } }
```

`e2e.yml` (nightly `schedule` plus `workflow_dispatch`, not a PR gate; the same policy as `react-native-e2e-tests` §5)
builds a simulator/emulator binary with the `e2e` EAS profile above, installs it, and runs `maestro test .maestro/flows --include-tags critical --format junit` with Maestro
installed from the pinned version baked into the runner image (a developer-run install, see `react-native-e2e-tests`),
then uploads the JUnit report and screenshots. Secrets reach flows through the environment, never `-e` on the command line.
This workflow is a pattern, not exercised here.

## 3. Release (tag driven)

```yaml
# .github/workflows/release.yml
name: release
on: { push: { tags: ['v*.*.*'] } }
permissions: { contents: read }
jobs:
  release:
    runs-on: ubuntu-latest
    environment: production        # manual approval gate
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v7
        with: { node-version-file: .nvmrc, cache: npm }
      - uses: expo/expo-github-action@v8
        with: { eas-version: <current>, token: '${{ secrets.EXPO_TOKEN }}' }
      - run: npm ci && npm run verify
      - run: eas build --profile production --platform all --non-interactive --auto-submit
```

**A tag pushed by a workflow using the default `GITHUB_TOKEN` does not trigger `on: push: tags`** (GitHub does not start
workflows from events created with that token). If release-please (or any bot) creates the tag, either give it a PAT or
GitHub App token (`token: '${{ secrets.RELEASE_BOT_TOKEN }}'`), or run the build as a job in the same workflow gated on the
action's `release_created` output. Test the trigger once on a throwaway tag before relying on it.

Fastlane alternative: macOS runner for iOS (`bundle exec fastlane ios release`, signing via `match`),
Linux for Android (`fastlane android release`, keystore from secrets). Keep lanes thin; logic stays in scripts.

## 4. Versioning and build numbers

- **Version** (`1.4.0`) is semantic and comes from one place: the release PR (release-please) bumps `package.json`, and
  `app.config.ts` reads it (`import { version } from './package.json'; export default { expo: { version, ... } }`). The tag
  marks the released commit. With `appVersionSource: remote`, EAS owns only the build number, not `version`. Shell variables
  on the runner (such as one derived from the tag) do not reach EAS cloud builds, so do not rely on them there; they do
  work for Fastlane or `eas build --local`. Never hand-edit the version.
- **Build number** (iOS `buildNumber`, Android `versionCode`) must increase monotonically per upload;
  let EAS `autoIncrement` with `appVersionSource: remote` own it, or derive from `${{ github.run_number }}` for Fastlane.
- One tag, one release; never rebuild a tag. Generate release notes from Conventional Commits.

## 5. OTA update stance

OTA (EAS Update; Microsoft App Center CodePush was retired in 2025, so do not start new work on it) may ship **JS and asset changes only**, never native changes, and only to
the matching `runtimeVersion`. Use channels (`preview`, `production`), roll out gradually, keep a rollback
(`eas update:republish`). Store-policy-sensitive changes (new features that change app purpose) go through
the store. Every OTA passes the same `verify` gate.

## 6. Secrets and hygiene

- Store tokens, keystores and certificates in GitHub Secrets/Environments; scope per environment.
- Least privilege: every workflow declares `permissions:` (`contents: read` unless a job needs more, scoped per job); pin third-party actions to a major version or SHA, and tools such as `eas-cli` to an exact version, never `latest`.
- Cache `~/.npm` via `setup-node`; cache Gradle/CocoaPods only on self-hosted native builds.
- Upload test reports, Maestro artefacts and source maps (to Sentry) as artifacts of the run.

## Do / Don't

- ✅ One pipeline definition; local `npm run verify` equals CI.
- ✅ Protect the default branch; require `verify` and review.
- ✅ Gate production builds on an environment approval.
- ❌ `continue-on-error` or skipped gates for "hotfixes".
- ❌ Committing keystores, `.p8` keys or `.env` secrets.
- ❌ Hand-edited build numbers.
- ❌ OTA updates that need a new native module.

## Cross-references

- `react-native-static-analysis`: the gate commands run here.
- `react-native-unit-tests`, `react-native-e2e-tests`: test stages.
- `react-native-observability`: source map upload and release health per version.
- `react-native-security`: secrets and signing hygiene.

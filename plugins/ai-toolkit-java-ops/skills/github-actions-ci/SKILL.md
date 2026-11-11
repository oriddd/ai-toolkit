---
name: github-actions-ci
description: >
  Java / Spring Boot CI on GitHub Actions — build, test, image, release, commit-lint and dependency-scan workflows on
  GitHub-hosted runners. Use when the repo builds on GitHub Actions; do not also load `ci` (Jenkins) — pick one per repo.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: [static-analysis]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-11
---

# GitHub Actions CI Skill
Equivalent of the Jenkins `ci` skill for organizations standardized on
GitHub Actions. Produces four workflow files under `.github/workflows/`.

**Action pinning.** Every `uses:` below is written `owner/action@<sha>  # vX.Y.Z`. Replace `<sha>` with the full
40-character commit SHA of the action's **current** release and put that release tag in the comment (for example
`actions/checkout` is on v7 and `actions/setup-java` on v6 as of November 2026). Tags can be re-pointed silently; a SHA cannot.
Let Dependabot / Renovate (`github-actions` ecosystem) bump the SHA and the comment together.

**`{{version}}` is literal.** In `image.yml`, `pattern={{version}}` is `docker/metadata-action` syntax, not a scaffold
placeholder — leave it as is when generating the file.

## 1. `build.yml` — every push / PR

```yaml
name: build
on:
  push:
    branches: [main]
  pull_request: {}
permissions:
  contents: read
  actions: read          # dorny/test-reporter reads the workflow run
  checks: write          # dorny/test-reporter publishes a check run (read-only on PRs from forks)
concurrency:
  group: build-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}   # never cancel a running main build
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<sha>  # vX.Y.Z
        with:
          fetch-depth: 0
          persist-credentials: false
      - uses: actions/setup-java@<sha>  # vX.Y.Z
        with:
          distribution: temurin
          java-version: '21'
          cache: maven
      # verify = unit + component (Surefire), integration (Failsafe) and the Jacoco check.
      # integration-tests policy: PRs that touch no client/ package or repository may add -DskipITs.
      - run: mvn -B -ntp verify
      - uses: actions/upload-artifact@<sha>  # vX.Y.Z
        if: failure()
        with:
          name: test-reports
          path: |
            **/target/surefire-reports
            **/target/failsafe-reports
      - uses: dorny/test-reporter@<sha>  # vX.Y.Z
        # a PR from a fork gets a read-only token and cannot create the check run: skip it there
        if: ${{ !cancelled() && (github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository) }}
        with:
          name: tests
          path: '**/target/surefire-reports/*.xml,**/target/failsafe-reports/*.xml'
          reporter: java-junit
```

Public repositories that take fork PRs and still want the report: upload the XML reports as an artifact on every run
and publish them from a second workflow on `workflow_run` (the "Recommended setup for public repositories" in the
`dorny/test-reporter` README).

## 2. `image.yml` — build + scan + push + sign + attest (release tags only)

The image is scanned **before** it is pushed: a HIGH/CRITICAL finding stops the release with nothing published.

```yaml
name: image
on:
  push:
    tags: ['v*']
permissions:
  contents: read
  packages: write
  id-token: write        # keyless cosign signing (OIDC)
jobs:
  image:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<sha>  # vX.Y.Z
        with:
          persist-credentials: false   # the job runs third-party actions with packages: write
      - uses: actions/setup-java@<sha>  # vX.Y.Z
        with:
          distribution: temurin
          java-version: '21'
          cache: maven
      # Full verify on the released commit, so the coverage gate also guards what ships
      - run: mvn -B -ntp verify
      - name: Image name (GHCR needs lowercase)
        run: echo "IMAGE=ghcr.io/${GITHUB_REPOSITORY,,}" >> "$GITHUB_ENV"
      - uses: docker/setup-buildx-action@<sha>  # vX.Y.Z
      - uses: docker/login-action@<sha>  # vX.Y.Z
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - id: meta
        uses: docker/metadata-action@<sha>  # vX.Y.Z
        with:
          images: ${{ env.IMAGE }}
          tags: type=semver,pattern={{version}}   # v1.4.0 → 1.4.0 (release-versioning §6)
      - name: Build for scanning (not pushed)
        uses: docker/build-push-action@<sha>  # vX.Y.Z
        with:
          context: .
          load: true
          tags: ${{ env.IMAGE }}:scan
      - uses: aquasecurity/trivy-action@<sha>  # vX.Y.Z — always SHA-pin this one
        with:
          image-ref: ${{ env.IMAGE }}:scan
          severity: 'HIGH,CRITICAL'
          exit-code: '1'
      - id: build                                  # build-push-action exposes the pushed digest
        name: Push (layers come from the build cache)
        uses: docker/build-push-action@<sha>  # vX.Y.Z
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}  # OCI labels (source, revision, version)
      - uses: sigstore/cosign-installer@<sha>  # vX.Y.Z
      - run: cosign sign --yes "${IMAGE}@${{ steps.build.outputs.digest }}"
      - uses: anchore/sbom-action@<sha>  # vX.Y.Z
        with:
          image: ${{ env.IMAGE }}@${{ steps.build.outputs.digest }}
          format: spdx-json
          output-file: sbom.spdx.json
      - name: Attest the SBOM to the image
        run: cosign attest --yes --type spdxjson --predicate sbom.spdx.json "${IMAGE}@${{ steps.build.outputs.digest }}"
```

## 3. `release.yml` — release-please

```yaml
name: release
on:
  push:
    branches: [main]
permissions:
  contents: write
  pull-requests: write
jobs:
  rp:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@<sha>  # vX.Y.Z
        # A tag pushed with the default GITHUB_TOKEN does not trigger other
        # workflows, so image.yml would never run. Use a PAT or GitHub App token.
        with:
          token: ${{ secrets.RELEASE_PLEASE_TOKEN }}
```

No `release-type` input: setting it switches the action to single-package mode, which ignores the manifest config
(release-please-action README, "manifest — do not set `release-type`"), so the Helm chart's `appVersion` would never be
bumped. Commit `release-please-config.json` (`"release-type": "maven"` plus the `helm-chart/Chart.yaml` `extra-files`
entry) and `.release-please-manifest.json` from `release-versioning` §3 (`ai-toolkit-workflow`) at the repo root.

## 4. `lint-commits.yml` — Conventional Commits (`commitlint` check)

Copy `lint-commits.yml` from `release-versioning` §1 (`ai-toolkit-workflow`): job name `commitlint`, `fetch-depth: 0`,
`on: pull_request`. It provides the `commitlint` status that branch protection requires below; SHA-pin its actions
like the workflows above. Make the check required only once the workflow exists.

## 5. Cross-cutting

- **Dependency scanning**: enable Dependabot via `.github/dependabot.yml`
  for `maven`, `github-actions`, `docker`.
- **Code-scanning**: enable CodeQL via `.github/workflows/codeql.yml` (one
  liner from the GitHub catalogue).
- **Branch protection**: `main` requires the `build` and `commitlint` checks (jobs above) +
  one approval + linear history.
- **Status badges** in `README.md`:
  ```
  ![build](https://github.com/<org>/<repo>/actions/workflows/build.yml/badge.svg)
  ```

## Pairing with the Jenkins `ci` skill

A repo applies **one** of `ci` (Jenkins) or `github-actions-ci`. Never both
— two pipelines producing two images means two opportunities to drift.

## Do / Don't

✅ Pin actions to a SHA in production-critical workflows; tags can be
re-pointed silently.
✅ Use `concurrency` to cancel in-progress builds on PR force-push — saves
runner minutes (PRs only; never cancel a `main` build).
✅ Signed + SBOM-attested images are the default, not an opt-in (`cosign sign` + `cosign attest` in `image.yml`).
✅ Give every workflow an explicit least-privilege `permissions:` block and `persist-credentials: false` on checkout.
❌ Never put secrets in workflow files — use `secrets.*` and OIDC where
possible.
❌ Never run integration tests on every PR if they require external
infrastructure — gate them by label or schedule.


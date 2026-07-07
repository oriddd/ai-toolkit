---
name: github-actions-ci
description: Alternative to the Jenkins-based `ci` skill — GitHub Actions workflows for build / test / image / release / dependency-scan. Vendor-neutral; uses only the public GitHub-hosted runners and standard actions. Pair with `ci` (Jenkins) by picking one per repo, not both.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: [static-analysis]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# GitHub Actions CI Skill (public)

Equivalent of the Jenkins `ci` skill for organizations standardized on
GitHub Actions. Produces three workflow files under `.github/workflows/`.

## 1. `build.yml` — every push / PR

```yaml
name: build
on:
  push: { branches: [main] }
  pull_request: {}
concurrency: { group: build-${{ github.ref }}, cancel-in-progress: true }
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: 21, cache: maven }
      - run: mvn -B -ntp -q verify
      - uses: actions/upload-artifact@v4
        if: failure()
        with: { name: surefire-reports, path: '**/target/surefire-reports' }
      - uses: dorny/test-reporter@v1
        if: always()
        with: { name: tests, path: '**/target/surefire-reports/*.xml', reporter: java-junit }
```

## 2. `image.yml` — build + scan + sign + push (release tags only)

```yaml
name: image
on: { push: { tags: ['v*'] } }
permissions: { contents: read, packages: write, id-token: write }
jobs:
  image:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: 21, cache: maven }
      - run: mvn -B -q -DskipTests package
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with: { registry: ghcr.io, username: ${{ github.actor }}, password: ${{ secrets.GITHUB_TOKEN }} }
      - id: meta
        uses: docker/metadata-action@v5
        with: { images: ghcr.io/${{ github.repository }} }
      - uses: docker/build-push-action@v6
        with: { context: ., push: true, tags: ${{ steps.meta.outputs.tags }} }
      - uses: aquasecurity/trivy-action@0.24.0
        with: { image-ref: ghcr.io/${{ github.repository }}:${{ github.ref_name }}, severity: HIGH,CRITICAL, exit-code: '1' }
      - uses: sigstore/cosign-installer@v3
      - run: cosign sign --yes ghcr.io/${{ github.repository }}@${{ steps.meta.outputs.digest }}
      - uses: anchore/sbom-action@v0
        with: { image: ghcr.io/${{ github.repository }}:${{ github.ref_name }}, format: spdx-json }
```

## 3. `release.yml` — release-please

```yaml
name: release
on: { push: { branches: [main] } }
permissions: { contents: write, pull-requests: write }
jobs:
  rp:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        with: { release-type: maven }
```

## 4. Cross-cutting

- **Dependency scanning**: enable Dependabot via `.github/dependabot.yml`
  for `maven`, `github-actions`, `docker`.
- **Code-scanning**: enable CodeQL via `.github/workflows/codeql.yml` (one
  liner from the GitHub catalogue).
- **Branch protection**: `main` requires `build` + `commitlint` checks +
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
runner minutes.
✅ Signed + SBOM-attested images are the default, not an opt-in.
❌ Never put secrets in workflow files — use `secrets.*` and OIDC where
possible.
❌ Never run integration tests on every PR if they require external
infrastructure — gate them by label or schedule.


# Contributing to the Skills Catalogue
We welcome improvements to our patterns and skills!
## How to contribute
1. **New Skills**: If you identify a recurring pattern not yet captured, propose a new skill in `plugins/*/skills/`. Follow `AUTHORING.md`.
2. **Bug Fixes**: Fix typos or incorrect code samples in existing skills.
3. **Templates**: Improve the scaffold templates in `*/templates/`.
## Authoring Rules
- Keep it **vendor-neutral**. No employer-, product- or environment-specific names, hosts or code.
- Java 21 / Spring Boot 3 is the reference language; Python and React Native follow `LANGUAGE_CONTRACT.md`.
- Run the same gates as CI before submitting: `bash tools/validate-skills.sh && python3 tools/build-indexes.py --check && python3 tools/build-evals.py --check && python3 tools/check-links.py && bash tools/test-hooks.sh && bash tools/check-repo-hygiene.sh && bash tools/check-versions.sh origin/main`.
- Bump `version` in `.claude-plugin/plugin.json` of every plugin whose content you change — installed users only receive changes when the version changes.
- Use `ships_templates: true` if you add files to the `templates/` subfolder.
- Bump the skill's frontmatter `version` only when its contract changes (`AUTHORING.md` §2), and set `last_reviewed` only
  after a full review of the skill (`AUTHORING.md` §9) — never just because you edited it.
## Releasing
Plugin versions and the catalogue version move separately. Every PR bumps the `plugin.json` version of each plugin it touches and adds
entries under `## [Unreleased]` in `docs/CHANGELOG.md`; `tools/check-versions.sh` prints a NOTE while `metadata.version` in
`.claude-plugin/marketplace.json` still equals the last release. To cut a release, in one commit: choose the next SemVer, set
`metadata.version` in `marketplace.json` to it, rename `[Unreleased]` to `## [X.Y.Z] - date` and add an empty `## [Unreleased]` above it
(`tools/validate-skills.sh` fails when `metadata.version` and the latest released heading differ), run the CI gates above, then tag `vX.Y.Z`.
A release is complete only when its git tag exists. For every `## [x.y.z]` heading you add to `docs/CHANGELOG.md`:
1. Merge the release PR to `main` (all gates above green, plugin versions bumped, `[Unreleased]` renamed to `[x.y.z] - date`).
2. Tag the merge commit and push the tag: `git tag -a vx.y.z -m "vx.y.z" <merge-commit> && git push origin vx.y.z`.
3. Confirm with `git ls-remote --tags origin vx.y.z`. `bash tools/check-versions.sh` prints a NOTE when the latest CHANGELOG release has no matching tag.
## Pre-release check of the Java templates
Run `tools/render-java-proof.sh` before a release, and after any change under `plugins/ai-toolkit-java-*/**/templates/` or to the
pom / static-analysis / persistence / messaging / permissions / external-client / component-tests skills. It is a maintainer tool, **not a CI step**: the
integration part needs Docker.

It renders every shipped Java template into one fresh Spring Boot 3.5.16 service (the `ci` pom with the `static-analysis` plugins and the
dependencies of each skill merged in, exception handling, permissions with the resource server, persistence + Flyway + outbox, Kafka messaging with the
idempotent consumer, the external-client cache adapter and OAuth2 client, a health indicator, data-privacy, security-hardening, request-metrics, graceful-shutdown, rate-limiting, component tests, `ArchitectureTest`) plus a small sample domain,
runs `mvn spotless:apply` once (rendered code is not pre-formatted), then `mvn verify`: Spotless check, Error Prone + NullAway at ERROR, SpotBugs,
Checkstyle, unit, component and ArchUnit tests, the Jacoco per-class gate (85 % line / 75 % branch) and the PIT gate (>= 75 %). It exits non-zero on the first red gate and prints
test counts, Jacoco and PIT totals.

```sh
tools/render-java-proof.sh --target /tmp/java-proof            # unit + component tests, all static gates (about 2 minutes)
tools/render-java-proof.sh --target /tmp/java-proof --with-it  # also the *IT tests (Postgres 16, apache/kafka:3.9.1, redis:7-alpine, OAuth2 stubs, broker pause)
```

Needs JDK 21 (`JAVA_HOME`, or an installed one is found), Maven, and for `--with-it` a running Docker or Colima. Maven runs offline when the
Boot parent is in `~/.m2`; pass `--online` otherwise. A red run means a template or a skill instruction fails the toolkit's own gates when applied
together with the others: fix the template, never the rendered project. The final summary lists exactly which skills are executed, which classes come
from shipped templates versus the embedded sample, and which shipped Java templates or skills are not executed (prose-only skills such as
`resilience-patterns` and `observability`); read it instead of assuming coverage. Run-mode limits are printed too: the `*IT` classes and the Redis adapter need
`--with-it`, and graceful shutdown closes the Spring context rather than signalling a forked JVM.
## Code of Conduct
Be professional and constructive.

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
## Code of Conduct
Be professional and constructive.

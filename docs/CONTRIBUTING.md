# Contributing to the Skills Catalogue
We welcome improvements to our patterns and skills!
## How to contribute
1. **New Skills**: If you identify a recurring pattern not yet captured, propose a new skill in `plugins/*/skills/`. Follow `AUTHORING.md`.
2. **Bug Fixes**: Fix typos or incorrect code samples in existing skills.
3. **Templates**: Improve the scaffold templates in `*/templates/`.
## Authoring Rules
- Keep it **vendor-neutral**. No employer-, product- or environment-specific names, hosts or code.
- Java 21 / Spring Boot 3 is the reference language; Python and React Native follow `LANGUAGE_CONTRACT.md`.
- Run the same gates as CI before submitting: `bash tools/validate-skills.sh && python3 tools/check-links.py && bash tools/test-hooks.sh && bash tools/check-repo-hygiene.sh && bash tools/check-versions.sh origin/main`.
- Bump `version` in `.claude-plugin/plugin.json` of every plugin whose content you change — installed users only receive changes when the version changes.
- Use `ships_templates: true` if you add files to the `templates/` subfolder.
- Update the frontmatter `version` and `last_reviewed` date.
## Code of Conduct
Be professional and constructive.

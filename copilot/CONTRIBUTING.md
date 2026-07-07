# Contributing to the Skills Catalogue
We welcome improvements to our patterns and skills!
## How to contribute
1. **New Skills**: If you identify a recurring pattern not yet captured, propose a new skill in `public/skills/`. Follow `AUTHORING.md`.
2. **Bug Fixes**: Fix typos or incorrect code samples in existing skills.
3. **Templates**: Improve the scaffold templates in `*/templates/`.
## Authoring Rules
- Keep it **vendor-neutral**. No organization-specific terms.
- Focus on **Java 21 / Spring Boot 3**.
- Ensure `bash public/skills/validate-skills.sh` passes before submitting.
- Use `ships_templates: true` if you add files to the `templates/` subfolder.
- Update the frontmatter `version` and `last_reviewed` date.
## Code of Conduct
Be professional and constructive.

---
name: context-maintenance
description: Maintain project context documentation including architecture, standards, build plans, and progress tracking. Use when adding features, changing architecture, or updating project status to keep context up-to-date for AI assistants and team members.
tier: must
applies_to: [rest, event, scheduler, library, monolith, worker, cli, mobile]
depends_on: [documentation-and-adr]
ships_templates: true
hitl: false
version: 1.1
last_reviewed: 2026-11-15
---

# Context Maintenance Skill

Use this skill to maintain the `context/` documentation folder, ensuring all project knowledge stays current and accessible.

## When to Use

Apply this skill when adding new features or components, changing architecture or design patterns, updating dependencies or the technology stack, completing milestones or sprints, discovering new technical debt or issues, onboarding new team members, or updating build processes or CI/CD pipelines.

## Context Documentation Structure

```
context/
├── README.md              # Documentation index
├── project-overview.md    # High-level project summary
├── architecture.md        # System design & patterns
├── code-standards.md      # Coding conventions
├── build-plan.md         # Development & deployment
├── library-docs.md       # Dependency documentation
├── progress-tracker.md   # Status & metrics
├── system-context.md     # C4 system context diagram (Mermaid)
├── component-diagram.md  # C4 component diagram (Mermaid)
├── domain-flow.md        # Main flow sequence diagram (Mermaid)
├── dependencies.md       # Upstream / downstream systems and infrastructure
├── glossary.md           # Ubiquitous language
├── runbooks.md           # Operator procedures
├── slo.md                # SLO summary (canonical table: docs/SLO.md)
└── validate-context.sh   # Fails while a (REQUIRED) section is still empty
```

### Starting from the templates

This skill ships blank scaffolds in [`templates/context/`](templates/context/README.md). Copy the folder to the repo
root as `context/`, fill every `(REQUIRED)` section (the prompts are HTML comments, which do not count as content),
then run `bash context/validate-context.sh` — it fails until each required section has real content. Sections marked
`(REQUIRED for services)` (SLOs, disaster recovery) are optional when `project-overview.md` has the line
`Project type: library`, `cli` or `mobile`. The validator is for the project's copied `context/` folder; the blank
templates fail it by design.


## Reference map

Load only the file you need.

| Section | Topic | Load when | File |
| --- | --- | --- | --- |
| Update Triggers | One worked example per trigger | writing the actual edit for a trigger | [`references/update-examples.md`](./references/update-examples.md) |
| AI Assistant Usage, Templates, Examples | Prompts, feature-doc and tech-debt templates, three worked updates | asking an assistant for updates or adding a feature doc | [`references/update-examples.md`](./references/update-examples.md) |
| Generating / Viewing Diagrams | Mermaid CLI, IDE preview | the developer needs an image or a preview | [`references/diagram-viewing.md`](./references/diagram-viewing.md) |
| Validation, Automation | Link and Mermaid checks, quality criteria, pre-commit reminder, CI stage | wiring or running the checks | [`references/validation-and-automation.md`](./references/validation-and-automation.md) |


## Update Triggers

### 1. Feature Addition

**Files to Update:**
- `project-overview.md` - Add to features list
- `architecture.md` - Document new components
- `code-standards.md` - Add new patterns if introduced
- `progress-tracker.md` - Update milestones
- `*.md` - Update relevant diagrams (Mermaid)

### 2. Architecture Change

**Files to Update:**
- `architecture.md` - Update design patterns, component structure
- Diagrams (Mermaid in `context/*.md`; any `*.puml` if the project uses PlantUML) - Reflect new architecture
- `code-standards.md` - Update if patterns change
- `progress-tracker.md` - Note as technical change

### 3. Dependency Changes

**Files to Update:**
- `library-docs.md` - Document new libraries or remove old ones
- `build-plan.md` - Update if build process changes
- `progress-tracker.md` - Note technical debt if needed

### 4. Sprint Completion

**Files to Update:**
- `progress-tracker.md` - Mark milestones complete, update metrics
- `CHANGELOG.md` - Append new version entries

## Maintenance Checklist

### Weekly Review
- [ ] Update `progress-tracker.md` with sprint progress
- [ ] Review technical debt register
- [ ] Update metrics (test coverage, mutation score, etc.)
- [ ] Append to `CHANGELOG.md` for any changes (unless a release bot owns it)

### After Major Changes
- [ ] Update affected documentation files
- [ ] Regenerate UML diagrams if architecture changed
- [ ] Update code examples if patterns changed
- [ ] Verify cross-references still valid
- [ ] Update "Last Updated" dates

### Monthly Review
- [ ] Full documentation review for accuracy
- [ ] Remove outdated information
- [ ] Add discovered patterns/solutions
- [ ] Update technical debt priorities
- [ ] Review and update metrics targets

## UML Diagram Maintenance (Mermaid)

### When to Update Diagrams

**system-context.md** - Update when:
- New external systems are integrated
- System boundaries change
- Actor roles change

**component-diagram.md** - Update when:
- New internal components added
- Component relationships change
- Technology choices change

**domain-flow.md** - Update when:
- Main flow logic changes
- New steps added to the primary use case
- Error handling changes

Generating images (`mmdc`) and previewing diagrams in an IDE: [`references/diagram-viewing.md`](./references/diagram-viewing.md). Most platforms render Mermaid natively, so no generation step is required.


## CHANGELOG Maintenance

The `CHANGELOG.md` is **append-only** at the top (under `[Unreleased]`).

> **Release bot:** when release-please / semantic-release owns the changelog, do not edit it by hand — not the weekly append, not the release
> rename (see `release-versioning`). The format is the one in `release-versioning` §5, hand-maintained or
> bot-generated: sections named after the Conventional Commit type (Features, Bug Fixes, …) plus Deprecations. An
> existing hand-maintained changelog that already uses Keep a Changelog sections (Added, Changed, Fixed, …) keeps them —
> never mix the two schemes in one file.

### Adding Entries

```markdown
## [Unreleased]

### Features
- scope: new feature description (#PR)

### Bug Fixes
- scope: bug fix description (#PR)

### Deprecations
- `legacyThing` — removed in 2.0
```

Other changes go under the section of their commit type (e.g. `### Performance Improvements` for `perf`).

### Release Process

When releasing a version:

1. **Rename [Unreleased] to version**:
   ```markdown
   ## [1.0.0] — 2026-07-15
   ```

2. **Add new [Unreleased] section** at top:
   ```markdown
   ## [Unreleased]
   
   ## [1.0.0] — 2026-07-15
   ```

3. **Update progress-tracker.md** to match


## Best Practices

### 1. Keep It Current
- Update docs as you code, not after
- Small frequent updates > large occasional ones
- Set reminders for weekly reviews

### 2. Be Specific
- Include code examples
- Reference actual file paths
- Use concrete numbers for metrics

### 3. Cross-Reference
- Link related documents
- Reference skills from documentation
- Link to code when helpful

### 4. Think About Readers
- New team members: Do they have enough context?
- AI assistants: Is the information structured?
- Future you: Will this make sense in 6 months?

### 5. Version Important Changes
- Major architecture changes: Create ADR (Architecture Decision Record)
- Breaking changes: Document migration path
- Deprecations: Note removal timeline

## Related Skills

- [uml-diagram](../uml-diagram/SKILL.md) - Create/update UML diagrams
- Code quality review — Java `quality-review`; Python and React Native: the `python-code-review` / `react-native-code-review` agents
- [documentation-and-adr](../documentation-and-adr/SKILL.md) - General documentation


## Validation

Run `bash context/validate-context.sh` after every change (it fails while a `(REQUIRED)` section is empty). Link, Mermaid and date checks, the quality criteria, the pre-commit reminder and the CI stage are in [`references/validation-and-automation.md`](./references/validation-and-automation.md).


## Support

For questions about:
- **Mermaid syntax**: https://mermaid.js.org/
- **C4 model**: https://c4model.com/
- **Keep a Changelog**: https://keepachangelog.com/
- **ADRs**: https://adr.github.io/


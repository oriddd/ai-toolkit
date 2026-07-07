---
name: context-maintenance
description: Maintain project context documentation including architecture, standards, build plans, and progress tracking. Use when adding features, changing architecture, or updating project status to keep context up-to-date for AI assistants and team members.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: [documentation-and-adr]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-06-28
---

# Context Maintenance Skill

Use this skill to maintain the `context/` documentation folder, ensuring all project knowledge stays current and accessible.

## When to Use

Apply this skill when:
- ✅ Adding new features or components
- ✅ Changing architecture or design patterns
- ✅ Updating dependencies or technology stack
- ✅ Completing milestones or sprints
- ✅ Discovering new technical debt or issues
- ✅ Onboarding new team members
- ✅ Updating build processes or CI/CD pipelines

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
└── domain-flow.md        # Main flow sequence diagram (Mermaid)
```

## Update Triggers

### 1. Feature Addition

**Files to Update:**
- `project-overview.md` - Add to features list
- `architecture.md` - Document new components
- `code-standards.md` - Add new patterns if introduced
- `progress-tracker.md` - Update milestones
- `*.md` - Update relevant diagrams (Mermaid)

**Example:**
```markdown
# In project-overview.md, add:
### Key Features
- REST API for resource management
- Integration with external services
- **NEW: Async processing queue** ← Add this
```

### 2. Architecture Change

**Files to Update:**
- `architecture.md` - Update design patterns, component structure
- `*.puml` diagrams - Reflect new architecture
- `code-standards.md` - Update if patterns change
- `progress-tracker.md` - Note as technical change

**Example:**
When adding a caching layer:
```markdown
# In architecture.md:
### Key Components

#### 3. Caching Layer
- In-memory cache for frequently converted documents
- Redis-backed distributed cache
- Cache invalidation strategy
```

### 3. Dependency Changes

**Files to Update:**
- `library-docs.md` - Document new libraries or remove old ones
- `build-plan.md` - Update if build process changes
- `progress-tracker.md` - Note technical debt if needed

**Example:**
```markdown
# In library-docs.md:
### Cache Libraries

#### Redis (New)
- **Purpose**: Distributed caching
- **Configuration**: `spring.redis.*` properties
- **Usage**: `@Cacheable` annotations
```

### 4. Sprint Completion

**Files to Update:**
- `progress-tracker.md` - Mark milestones complete, update metrics
- `CHANGELOG.md` - Append new version entries

**Example:**
```markdown
# In progress-tracker.md:
### ✅ Phase 3: Quality & Testing (Completed)
- [x] Mutation testing - 78% score achieved
- [x] Performance testing baseline established
```

## Maintenance Checklist

### Weekly Review
- [ ] Update `progress-tracker.md` with sprint progress
- [ ] Review technical debt register
- [ ] Update metrics (test coverage, mutation score, etc.)
- [ ] Append to `CHANGELOG.md` for any changes

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

### Generating Diagrams

Most platforms (GitHub, GitLab) render Mermaid natively from markdown files. No generation step is required!

If you need a static image for a document that doesn't support Mermaid:

```bash
# Install Mermaid CLI
npm install -g @mermaid-js/mermaid-cli

# Generate PNG from markdown file containing mermaid block
mmdc -i context/system-context.md -o system-context.png
```

### Viewing Diagrams

- **GitHub/GitLab**: View the `.md` file directly in the web interface.
- **VS Code**: Use "Markdown Preview Mermaid Support" extension.
- **IntelliJ IDEA**: Use "Mermaid" plugin.
- **Online**: Use the [Mermaid Live Editor](https://mermaid.live/).

## CHANGELOG Maintenance

The `CHANGELOG.md` is **append-only** at the top (under `[Unreleased]`).

### Adding Entries

```markdown
## [Unreleased]

### Added
- New feature description

### Changed
- What changed and why

### Fixed
- Bug fix description
```

### Release Process

When releasing a version:

1. **Rename [Unreleased] to version**:
   ```markdown
   ## [1.0.0] - 2026-07-15
   ```

2. **Add new [Unreleased] section** at top:
   ```markdown
   ## [Unreleased]
   
   ## [1.0.0] - 2026-07-15
   ```

3. **Update progress-tracker.md** to match

## AI Assistant Usage

### Providing Context

When working with AI assistants, reference context docs:

```
"Please review /context/architecture.md and /context/code-standards.md 
before implementing the new caching layer."
```

### Asking for Updates

```
"I just added async processing support. Please update:
- context/project-overview.md (features)
- context/architecture.md (new component)
- context/component-diagram.md (add queue component in mermaid)
- context/progress-tracker.md (milestone)
- CHANGELOG.md (new feature)"
```

### Quality Checks

Ask AI to verify:
```
"Review all context/ documentation and flag any outdated 
information or broken cross-references."
```

## Templates

### Adding New Feature Documentation

```markdown
## [Feature Name]

### Purpose
Brief description of what this feature does.

### Architecture
How it fits into the system:
- Component interactions
- Design patterns used
- Data flow

### Usage
Code examples showing how to use it:
\```java
public class Example {
    // Code example
}
\```

### Configuration
Required configuration:
\```yaml
feature:
  enabled: true
  timeout: 30s
\```

### Testing
How to test this feature:
- Unit test approach
- Integration test requirements
```

### Adding New Technical Debt

In `progress-tracker.md`:

```markdown
| TD-XXX | Description | Priority | Estimated Effort | Owner |
|--------|-------------|----------|------------------|-------|
| TD-006 | [Description] | [H/M/L] | Xd | TBD |
```

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
- [quality-review](../quality-review/SKILL.md) - Code quality review
- [documentation-and-adr](../documentation-and-adr/SKILL.md) - General documentation

## Validation

### Context Documentation Health Check

```bash
# Check for broken links (requires markdown-link-check)
npx markdown-link-check context/*.md

# Validate Mermaid syntax (requires mermaid-cli)
for f in context/*.md; do mmdc -i "$f" -o /dev/null; done

# Check for outdated dates (manual review)
grep -r "Last Updated" context/
```

### Quality Criteria

Good context documentation:
- ✅ Less than 3 months old
- ✅ No broken links
- ✅ Code examples compile
- ✅ Mermaid diagrams render correctly
- ✅ Metrics are current
- ✅ Cross-references valid
- ✅ No TODO markers

## Examples

### Example 1: Adding Redis Cache

**Files Updated:**
1. `project-overview.md`: Add Redis to tech stack
2. `architecture.md`: Document caching layer
3. `component-diagram.md`: Add cache component in Mermaid
4. `library-docs.md`: Document Redis client usage
5. `build-plan.md`: Add Redis to docker-compose
6. `progress-tracker.md`: Update milestone
7. `CHANGELOG.md`: Add to [Unreleased]

### Example 2: Completing Sprint

**Files Updated:**
1. `progress-tracker.md`: 
   - Mark completed stories ✅
   - Update metrics
   - Update sprint goals
2. `CHANGELOG.md`:
   - Move [Unreleased] to [0.4.0]
   - Add release date
   - Create new [Unreleased] section

### Example 3: Discovering Technical Debt

**Files Updated:**
1. `progress-tracker.md`:
   - Add row to technical debt register
   - Update debt ratio metric
2. `architecture.md`:
   - Add note about planned improvement
   - Document current limitation

## Automation Opportunities

### Git Hooks

Create a pre-commit hook to remind about docs:

```bash
#!/bin/bash
# .git/hooks/pre-commit

if git diff --cached --name-only | grep -q "src/main/java"; then
    echo "📝 Remember to update context/ documentation if needed!"
    echo "   - architecture.md for new components"
    echo "   - code-standards.md for new patterns"
    echo "   - progress-tracker.md for milestones"
fi
```

### CI Pipeline Check

Add to Jenkinsfile:

```groovy
stage('Documentation Check') {
    steps {
        sh 'npx markdown-link-check context/*.md'
        // Validate mermaid diagrams
        sh 'npm install -g @mermaid-js/mermaid-cli && for f in context/*.md; do mmdc -i "$f" -o /dev/null; done'
    }
}
```

## Support

For questions about:
- **Mermaid syntax**: https://mermaid.js.org/
- **C4 model**: https://c4model.com/
- **Keep a Changelog**: https://keepachangelog.com/
- **ADRs**: https://adr.github.io/


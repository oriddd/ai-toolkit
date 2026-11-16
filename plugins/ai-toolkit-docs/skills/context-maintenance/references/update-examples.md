# Context Maintenance — update examples, templates and AI prompts

Loaded from [`context-maintenance`](../SKILL.md).

## 1. Feature Addition — example

**Example:**
```markdown
# In project-overview.md, add:
### Key Features
- REST API for resource management
- Integration with external services
- **NEW: Async processing queue** ← Add this
```

## 2. Architecture Change — example

**Example:**
When adding a caching layer:
```markdown
# In architecture.md:
### Key Components

#### 3. Caching Layer
- In-memory cache for frequently exported invoices
- Redis-backed distributed cache
- Cache invalidation strategy
```

## 3. Dependency Changes — example

**Example:**
```markdown
# In library-docs.md:
### Cache Libraries

#### Redis (New)
- **Purpose**: Distributed caching
- **Configuration**: the settings the code reads — Java `spring.data.redis.*` (Spring Boot 3+; the old `spring.redis.*` keys are ignored), Python `REDIS_URL` in the settings class, React Native none (no client-side Redis)
- **Usage**: the entry point code must use — the project's cache port or wrapper, never the client directly
```

## 4. Sprint Completion — example

**Example:**
```markdown
# In progress-tracker.md:
### Phase 3: Quality & Testing (Completed)
- [x] Mutation testing - 78% score achieved
- [x] Performance testing baseline established
```

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
\```<language>
<code example in the project's language>
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
   - Mark completed stories
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


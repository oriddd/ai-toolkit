# How to Use This AI Toolkit

A practical guide for developers and AI agents using this skills catalogue
to build production-grade services faster. Most of this guide uses the Java 21 / Spring Boot
set (the most complete one); Python / FastAPI and React Native follow the same structure — see
[`LANGUAGE_CONTRACT.md`](./LANGUAGE_CONTRACT.md).

---

## What is this toolkit?

A **vendor-neutral catalogue of reusable coding patterns** (Skills) and
**documentation templates** (Context), shipped as Claude Code plugins: per-language sets for
Java 21 / Spring Boot, Python / FastAPI (experimental) and React Native (experimental), plus language-neutral
workflow, docs and quality plugins.

Core philosophy: every service you build should read like an open-source SDK —
clean interfaces, pluggable providers, SOLID by construction, testable in
isolation. The skills encode hard-won patterns so you never re-invent them.

---

## Quick navigation

| I want to… | Go here |
| --- | --- |
| **Toolkit overview — what lives where** | [`CHEATSHEET.md`](./CHEATSHEET.md) |
| CLI & IntelliJ tips for authoring skills | [`docs/SKILLS_CHEATSHEET.md`](./SKILLS_CHEATSHEET.md) |
| Understand every skill at a glance | [`REGISTRY.md`](REGISTRY.md) |
| Find the skill(s) for my task | [`INDEX_BY_USE_CASE.md`](INDEX_BY_USE_CASE.md) |
| Know what is mandatory vs optional | [`BACKEND_GUILD.md`](BACKEND_GUILD.md) |
| Use an AI agent for a specific task | [`plugins/ai-toolkit-java-agents/agents/`](agents/README.md) |
| Set up an AI agent for my whole project | [`AGENT_PROMPT.md`](agents/AGENT_PROMPT.md) |
| Bootstrap a new service's docs | [`context/`](../plugins/ai-toolkit-docs/skills/context-maintenance/templates/context) |
| Write or validate a new skill | [`AUTHORING.md`](AUTHORING.md) |

---

## 1. Setting up your AI agent

### Option A — Full catalogue (recommended for a new project)

Paste [`AGENT_PROMPT.md`](agents/AGENT_PROMPT.md) into your AI
tool's system prompt (GitHub Copilot workspace instructions, Cursor rules,
Claude project instructions, etc.).

The agent will:
- Classify your task automatically.
- Read the relevant skills in order.
- Validate every diff against the 24 non-negotiables.
- Update `context/` and `CHANGELOG.md` automatically.

### Option B — Topic agent (recommended for a focused task)

Pick the relevant agent from [`plugins/ai-toolkit-java-agents/agents/`](agents/README.md)
and paste it as your system prompt. Topic agents are concise and fast. The ten Java agents
(Python and React Native have their own `*-agents` plugins):

```
plugins/ai-toolkit-java-agents/agents/
  scaffold-repo.md           Create a new Spring Boot service from scratch
  new-endpoint.md            Add a REST endpoint
  new-feature.md             Implement a feature end-to-end
  new-kafka-consumer.md      Add a Kafka consumer (idempotent, DLQ, observability)
  new-microservice-client.md Integrate a new downstream service
  new-validation.md          Add an input-validation rule
  new-metric.md              Add a domain request metric
  test-writer.md             Write tests for existing classes (worker the other agents delegate to)
  code-review.md             Pre-PR quality review
  refactor.md                Migrate legacy code to catalogue patterns

plugins/ai-toolkit-docs/agents/   (language-neutral)
  update-context.md          Update docs + CHANGELOG after a code change
```

### Option C — Manual (for developers, no AI)

1. Find your task in [`INDEX_BY_USE_CASE.md`](INDEX_BY_USE_CASE.md).
2. Read each listed `plugins/*/skills/<name>/SKILL.md` in order.
3. Copy templates from `plugins/*/skills/<name>/templates/` and substitute
   `{{placeholder}}` tokens.
4. Check your work against the 24 non-negotiables in
   [`BACKEND_GUILD.md §4`](BACKEND_GUILD.md).

---

## 2. Bootstrapping a new project

```bash
# Copy the context folder into your new repo
cp -r plugins/ai-toolkit-docs/skills/context-maintenance/templates/context/ path/to/your-service/context/

# Fill in each template (search for "Placeholder content")
# Required: project-overview, architecture, code-standards, dependencies

# Validate the context is populated
bash plugins/ai-toolkit-docs/skills/context-maintenance/templates/context/validate-context.sh

# Run the skill validator after any skill edits
bash tools/validate-skills.sh
```

---

## 3. Understanding the skill tiers

| Tier | Meaning |
| --- | --- |
| **MUST** | Required in every service; PR fails without it |
| **SHOULD** | Required when the service has that feature |
| **MAY** | Optional; use when genuinely useful |
| **FOUNDATIONAL** | A pattern other skills build on (`strategy-registry-pattern`, `validation-pattern`) |

Current counts per tier are in [`REGISTRY.md`](REGISTRY.md) (generated).

Start with MUST skills when building a new service. The apply-order in
[`BACKEND_GUILD.md §2`](BACKEND_GUILD.md) tells you the right sequence.

---

## 4. The three architectural laws

Every skill in this catalogue reinforces these three laws:

### Law 1 — SOLID + Clean Code

- **Single Responsibility**: one class, one purpose.
- **Open/Closed**: add behaviour by adding a new class, never editing
  existing ones (new `MetricsRecorder`, new `Strategy`, new `Adapter`).
- **Dependency Inversion**: depend on abstractions (`*Port`, `*Strategy`,
  `*Recorder`), not concretions.

### Law 2 — Pluggable Architecture (Ports and Adapters)

Every external technology integration lives behind a project-owned port
interface. The vendor SDK is imported only inside its adapter class.
Swapping providers = changing one property. Multi-provider = adding a
composite adapter. Zero domain-code changes needed.

See [`pluggable-architecture`](../plugins/ai-toolkit-java-design/skills/pluggable-architecture/SKILL.md)

### Law 3 — SDK-Like Lego Bricks

Every module exposes a stable interface and defaults via
`@ConditionalOnMissingBean`, letting consumers override any bean.
Every layer has its own test contract. Replacing a brick never touches
its consumers.

See [`sdk-publishing`](../plugins/ai-toolkit-java-build/skills/sdk-publishing/SKILL.md) and
[`adapter-contract-tests`](../plugins/ai-toolkit-java-quality/skills/adapter-contract-tests/SKILL.md)

---

## 5. Common task recipes

| Task | Skills to read | Agent |
| --- | --- | --- |
| **New service from scratch** | `project-types` → `create-repo` → `code-structure` → `ci` → `cd` → `local-dev-experience` | `plugins/ai-toolkit-java-agents/agents/scaffold-repo.md` |
| New REST endpoint | `api-design` → `code-structure` → `exception-handling` → `permissions` → `input-validation` → `unit-tests` → `component-tests` | `plugins/ai-toolkit-java-agents/agents/new-endpoint.md` |
| New downstream service | `external-client` → `resilience-patterns` → `health-indicator` → `observability` | `plugins/ai-toolkit-java-agents/agents/new-microservice-client.md` |
| New DB entity | `persistence` → `domain-modeling` → `integration-tests` | `plugins/ai-toolkit-java-agents/agents/new-feature.md` |
| New validation rule | `input-validation` → `exception-handling` → `unit-tests` | `plugins/ai-toolkit-java-agents/agents/new-validation.md` |
| New domain metric | `request-metrics` → `observability` | `plugins/ai-toolkit-java-agents/agents/new-metric.md` |
| **New Kafka consumer** | `messaging` → `observability` → `graceful-shutdown` → `integration-tests` | `plugins/ai-toolkit-java-agents/agents/new-kafka-consumer.md` |
| Pre-PR review | `quality-review` → `BACKEND_GUILD §4` | `plugins/ai-toolkit-java-agents/agents/code-review.md` |
| Update docs | `context-maintenance` → `release-versioning` | `plugins/ai-toolkit-docs/agents/update-context.md` |
| **Refactor legacy** | `refactoring-playbook` → `quality-review` | `plugins/ai-toolkit-java-agents/agents/refactor.md` |
| Swap a technology | `pluggable-architecture` → `adapter-contract-tests` | `AGENT_PROMPT.md` |

---

## 6. Adding a new skill

When you see the same pattern repeated in a third service, extract it:

```bash
# 1. Create the folder in the plugin that owns the skill's phase (e.g. ai-toolkit-java-design)
mkdir -p plugins/ai-toolkit-java-design/skills/my-skill

# 2. Write SKILL.md following AUTHORING.md §2 — frontmatter keys:
#    name, description, tier (required, validated), applies_to, depends_on,
#    ships_templates, hitl, version, last_reviewed

# 3. Add a row to docs/README.md and name the skill in docs/INDEX_BY_USE_CASE.md

# 4. Validate — the tool tells you exactly what is missing
bash tools/validate-skills.sh

# 5. Regenerate auto-generated indexes
python3 tools/build-indexes.py
```

---

## 7. Validating the catalogue

```bash
# Validate all skills (frontmatter, links, template refs, indexes in sync)
bash tools/validate-skills.sh

# Rebuild REGISTRY.md and BACKEND_GUILD.md matrix/graph from frontmatter
python3 tools/build-indexes.py

# Validate the shipped context templates (required sections are non-empty)
bash plugins/ai-toolkit-docs/skills/context-maintenance/templates/context/validate-context.sh

# Links, hook behaviour, git modes
python3 tools/check-links.py && bash tools/test-hooks.sh && bash tools/check-repo-hygiene.sh
```

All of these must exit 0 before any PR that touches `plugins/` or `docs/` (CI runs them). In a service repo
that copied the templates, the validator lives at `context/validate-context.sh`.

---

## 8. Skill dependency map

```
code-structure
  ├─► api-design ──► openapi-first-codegen
  ├─► exception-handling ──► permissions ──► security-hardening
  ├─► spring-boot-conventions
  │     └─► pluggable-architecture
  │           ├─► observability
  │           ├─► persistence
  │           ├─► messaging
  │           ├─► external-client ──► resilience-patterns
  │           │                   ──► rate-limiting
  │           ├─► feature-flags
  │           └─► adapter-contract-tests
  ├─► unit-tests ──► component-tests ──► integration-tests
  ├─► input-validation
  └─► request-metrics

static-analysis ──► ci ──► cd ──► create-repo
static-analysis ──► quality-review ──► refactoring-playbook
unit-tests ─────────┘
```

Simplified (Java skills). The full graph is generated from `depends_on` in
[`BACKEND_GUILD.md`](BACKEND_GUILD.md) §1b.

---

## 9. Glossary

| Term | Meaning |
| --- | --- |
| **Skill** | An atomic, vendor-neutral coding pattern with examples, do/don'ts, optional templates |
| **Agent** | A pre-configured AI system prompt for a single focused task |
| **Port** | A project-owned interface isolating domain code from vendor SDKs |
| **Adapter** | A vendor-specific implementation of a port |
| **Lego brick** | A module with `@ConditionalOnMissingBean` defaults; fully replaceable by consumers |
| **TCK** | Technology Compatibility Kit — shared abstract test suite per port interface |
| **Non-negotiable** | A rule from `BACKEND_GUILD §4` that must hold in every PR |
| **HITL** | Human-in-the-loop — skill requires developer input before proceeding |
| **Context** | Living documentation in `context/` that agents use to understand the project |

---

## 10. FAQ

**Q: Can I use this with any AI tool?**
Yes. Paste `AGENT_PROMPT.md` (or a topic agent) into any AI tool's system
prompt — GitHub Copilot, Cursor, Claude, ChatGPT, Gemini, etc.

**Q: My project uses Kotlin. Does this apply?**
Most patterns apply directly. Spring Boot, SOLID, and architectural patterns
are language-agnostic. Kotlin-specific idioms (data classes, coroutines) are
not yet covered — a `kotlin-conventions` skill would be a good addition.

**Q: Can I add my own skills?**
Yes — in your own plugin or repository next to these plugins. Keep environment-specific
bindings (internal libraries, registries, auth token shapes) in your own plugin
so this catalogue stays vendor-neutral.

**Q: What if a user asks for something the skill forbids?**
Surface the conflict, cite the skill section, offer the canonical alternative.
Proceed only with explicit confirmation and an ADR under `docs/adr/`.
See `AGENT_PROMPT.md §7`.

**Q: How do I know the catalogue is up to date?**
Run `bash tools/validate-skills.sh`. It checks every skill's frontmatter,
internal links, and that REGISTRY.md and BACKEND_GUILD.md are in sync.


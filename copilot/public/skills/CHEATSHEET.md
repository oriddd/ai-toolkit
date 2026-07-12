# Skills Cheatsheet

Pro tips for **authoring and maintaining skills** — navigating, scaffolding, and
validating them using IntelliJ IDEA and the CLI. (Sits next to the skills it serves.)

---

## CLI — daily commands

```bash
# Skills tooling lives here — run from public/skills/
cd copilot/public/skills

bash validate-skills.sh          # lint all 45 skill frontmatters + links
python3 build-indexes.py         # regenerate REGISTRY.md + BACKEND_GUILD.md matrix
python3 build-indexes.py --check # dry-run (check without writing)

# Context templates have their own validator, next to the context/ folder:
bash ../../context/validate-context.sh
```

### Find things fast

```bash
# List all skills
ls copilot/public/skills/

# Search skill content by keyword
grep -r "idempotent" copilot/public/skills/ --include="*.md" -l

# Find which skills depend on a given skill
grep -r "depends_on.*messaging" copilot/public/skills/ --include="*.md"

# Find skills that ship templates
grep -rl "ships_templates: true" copilot/public/skills/

# Find all HITL skills
grep -rl "hitl: true" copilot/public/skills/
```

### Create a new skill scaffold

```bash
SKILL=my-skill
mkdir -p copilot/public/skills/$SKILL/templates
cat > copilot/public/skills/$SKILL/SKILL.md << 'EOF'
---
name: my-skill
description: One paragraph — what this skill prescribes and why.
tier: SHOULD
applies_to: [rest, event, monolith]
depends_on: [code-structure]
ships_templates: false
hitl: false
version: 0.1.0
last_reviewed: 2026-07-07
---

# My Skill

## 1. Purpose

## 2. Rules

## 3. Do / Don't

## 4. Examples
EOF

# Then validate:
bash copilot/public/skills/validate-skills.sh
```

---

## IntelliJ IDEA — navigation tips

### Find a skill by keyword
`Cmd+Shift+F` → scope: `copilot/public/skills` → search term

### Open a skill quickly
`Cmd+Shift+O` (Navigate → File) → type the skill name, e.g. `messaging/SKILL`

### Preview Markdown
Open any `SKILL.md` → click the split-pane icon (top right) → live preview side by side.

### Jump between sections in a skill
`Cmd+F12` (File Structure) while a `SKILL.md` is open — shows all headings as a
navigable list.

### Compare two skills
Right-click a `SKILL.md` in the Project panel → **Compare with…** → pick another skill.

### Find all skills that reference a skill by name
`Cmd+Shift+F` → search for `exception-handling` inside `copilot/public/skills/`
→ see every `depends_on` and cross-reference.

### Run validators from IntelliJ terminal
`Alt+F12` → open the built-in terminal — stays in the project root.

```bash
cd copilot/public/skills && bash validate-skills.sh
```

### Use a scratch file to draft a new skill
`Cmd+Shift+Alt+Insert` → New Scratch File → Markdown — write the skill draft,
then copy it into the proper `SKILL.md` file once ready.

---

## Pro tips

### Always regenerate indexes after editing frontmatter

Any change to frontmatter fields (`tier`, `depends_on`, `ships_templates`, etc.)
requires re-running the index builder or the validator will fail:

```bash
cd copilot/public/skills && python3 build-indexes.py
```

### Keep skill descriptions to one paragraph

The `description` field is what agents grep when selecting a skill.
Longer than one paragraph → agents may misclassify.

### Validate before you commit, not after

```bash
# Add this as a pre-commit alias
alias toolkit-check="cd $(git rev-parse --show-toplevel)/copilot && bash public/skills/validate-skills.sh && python3 public/skills/build-indexes.py --check && bash context/validate-context.sh"
```

### Use `#file` to test a skill in Copilot chat before publishing

```
#file /path/to/ai-toolkit/copilot/public/skills/my-new-skill/SKILL.md
Apply this skill to the code I'm about to paste.
```

Iterate on the skill based on the output before running the validator.

### The dependency graph is your apply-order

```
code-structure
  ├─► api-design ──► openapi-first-codegen
  ├─► exception-handling ──► permissions ──► security-hardening
  ├─► spring-boot-conventions
  │     └─► pluggable-architecture
  │           ├─► observability
  │           ├─► persistence
  │           ├─► messaging
  │           └─► external-client ──► resilience-patterns
  ├─► unit-tests ──► component-tests ──► integration-tests
  └─► request-metrics
```

Always add `depends_on` edges when a skill assumes another is already applied.
The agent uses this order to sequence its work.

### Keep agent files slim

Agents live next to their own cheatsheet in [`../agents/`](../agents/README.md).
Each agent file should stay under ~80 lines; if it grows, extract a new skill
and reference it. See [`../agents/CHEATSHEET.md`](../agents/CHEATSHEET.md).

### Three-rule test for a new skill

Before creating a new skill, check:
1. Does a third service already use this pattern? (two is coincidence, three is a pattern)
2. Can it be expressed without org-specific tools or libraries?
3. Is it genuinely different from an existing skill's scope?

If all three are yes → create it. If not → document it as a section in an existing skill.


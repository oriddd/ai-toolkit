# SKILL Authoring Guide

This document is the single source of truth for **how a `SKILL.md` is
structured**. The CI validator (`tools/validate-skills.sh`) mechanically
enforces the rules below, so a PR that violates them fails the build.

## 1. Directory layout

```
.claude-plugin/marketplace.json     ← lists every plugin
plugins/
└── ai-toolkit-<phase | lang-phase>/
    ├── .claude-plugin/plugin.json  ← name, description, version
    ├── skills/<skill-name>/
    │   ├── SKILL.md                ← required
    │   └── templates/              ← optional, only if SKILL.md ships files
    ├── agents/<agent>.md           ← agents only (ai-toolkit-java-agents)
    └── hooks/                      ← optional (<lang>-design: language routing hook; workflow: neutral rules)
docs/                               ← README (skill index), REGISTRY, BACKEND_GUILD,
                                      INDEX_BY_USE_CASE, AUTHORING, agents/
tools/                              ← build-indexes.py, validate-skills.sh, check-links.py
```

**Plugin boundary rule:** a plugin is installed on its own, so a `SKILL.md`
may link (`../other/SKILL.md`) only to skills in the *same* plugin. Refer to
skills in other plugins by name (`` `exception-handling` ``). The validator enforces this.

## 2. Frontmatter contract

Every `SKILL.md` **must** begin with YAML frontmatter, on line 1:

```yaml
---
name: <folder-name>          # MUST equal the parent directory name
description: <one-paragraph> # MUST be present; agents grep this to choose a skill
---
```

Rules (all enforced by the validator):

| Rule | Validator section |
| --- | --- |
| `name` field equals folder name | §2 |
| `description` field present and non-empty | §2 |
| Any markdown link `(./templates/<file>)` resolves | §3 |
| Index (`README.md`) has a row for the skill | §4 |
| `REGISTRY.md` has a row for the skill | §4 |
| `templates/` files use only `{{placeholder}}` syntax | §5 |

## 3. Required SKILL.md sections

A SKILL.md should contain, in roughly this order:

1. **Heading** — `# <Skill Name> Skill`
2. **When to use** — one sentence describing the triggering situation.
3. **Layout / shape** — code block showing the file/package structure
   the skill produces or expects.
4. **Dependencies** — minimal `pom.xml` snippet, only public Maven
   Central coordinates.
5. **Numbered sections** — `## 1. <Topic>`, `## 2. <Topic>`, … walking
   the pattern in apply-order. Use sub-headings `## Nb.` for variants
   so cross-references in `BACKEND_GUILD.md` stay stable.
6. **Anti-patterns / Do / Don't** — bullet list with ✅ / ❌ markers.
7. **Cross-references** — bullet list linking the other skills this
   skill leans on (use relative links: `../<other>/SKILL.md`).

## 4. Templating syntax

When a skill ships template files under `templates/`, the **only**
allowed placeholder syntax is double-curly:

```text
{{basePackage}}            // e.g. com.example.foo
{{basePackagePath}}        // e.g. com/example/foo
{{serviceName}}            // e.g. my-service
```

Forbidden alternatives (flagged by validator §5):

- `<basePackage>` / `<basePackagePath>` — collides with XML
- `__basePackage__` / `__basePackagePath__` — collides with Java
  reserved identifiers

Bare prose mentions like `path/to/templates/foo` in a SKILL.md are
fine — the validator only checks **clickable markdown links** of the
form `](./templates/<file>)`.

## 5. Authoring checklist

Before opening a PR that adds or modifies a SKILL.md:

- [ ] Folder name = `name` in frontmatter.
- [ ] `description:` is one paragraph and explains *when* to use the skill.
- [ ] Any `](./templates/<file>)` link resolves to a real file.
- [ ] `templates/` files use only `{{placeholder}}` syntax.
- [ ] `README.md` has a new row.
- [ ] `REGISTRY.md` has a new row (and updated total).
- [ ] `bash tools/validate-skills.sh` passes locally with zero errors.

## 6. Adding a brand-new skill (walkthrough)

```sh
SKILL=my-new-skill
mkdir -p $SKILL
cat > $SKILL/SKILL.md <<'EOF'
---
name: my-new-skill
description: One paragraph explaining what this skill does and when to apply it.
---

# My New Skill

## When to use
…

## 1. …
EOF

$EDITOR README.md   # add a row
$EDITOR REGISTRY.md        # add a row (and update total)

bash tools/validate-skills.sh
```

## 7. Marking a skill experimental / deprecated

Add a banner immediately after the frontmatter:

```markdown
> ⚠️ **Experimental.** API may change before promotion to stable.
```

```markdown
> 🚨 **Deprecated since 2026-07-01.** Use [`<replacement-skill>`](../<replacement>/SKILL.md).
```

The validator does not block on these — they are advisory.

## 5. Phases and languages

A plugin is one **phase** (workflow, docs, design, build, quality, ops, scaffold, agents), either
language-neutral (`ai-toolkit-workflow`) or per language (`ai-toolkit-<lang>-<phase>`). Put a skill in
the phase it belongs to — delivery workflow (commits, PRs, releases) never shares a plugin with
implementation (errors, validation) or testing. See [`LANGUAGE_CONTRACT.md`](./LANGUAGE_CONTRACT.md)
for naming, the required skills per language and the routing-hook convention.

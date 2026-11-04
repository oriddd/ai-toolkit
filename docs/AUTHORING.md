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
    │   ├── references/             ← optional, deep-dive sections loaded on demand (see §3b)
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
description: <one-paragraph> # MUST say WHEN to use it ("Use when …" / "Apply when …"); agents grep this to choose a skill
tier: should                 # lowercase: must | should | may | foundational
applies_to: [rest]           # project types
depends_on: []               # skills this one needs (the plugin must depend on their plugins)
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
   skill leans on (link skills of the *same plugin* with `../<other>/SKILL.md`; name skills of other plugins in backticks — §1).

## 3b. Keep SKILL.md small — move deep dives to `references/`

A skill's body is loaded in full every time it is invoked, and `depends_on` chains invoke several at once.
Keep `SKILL.md` to what must always be read; move code-heavy sections that are needed only when building one
part into `references/<topic>.md`.

- **Stays in `SKILL.md`:** frontmatter, *When to use*, any HITL / decision gate, the layout and layering
  overview, Do / Don't, cross-references and templates. Target **under ~12 KB**; `validate-skills.sh` fails a `SKILL.md` over 16 KB.
- **Moves to `references/`:** per-layer walkthroughs, long code samples, tests, growth paths.
- **Keep section numbers stable.** Other skills and `BACKEND_GUILD.md` cite `skill §N`; leave the `## N.` headings
  in the reference file and list every moved section in a reference-map table in `SKILL.md`
  (section, topic, *load when*, link). Say "load only the file you need".
- Link with relative paths (`](./references/<file>.md)`); `tools/check-links.py` verifies them. A reference file
  links back with `](../SKILL.md)` and has no frontmatter.

## 3c. Agents and tools

An agent without a `tools:` line inherits every tool. That is deliberate for implementers (`new-feature`, `refactor`,
`test-writer`, …): they edit files, run builds and load skills. **Review agents** (`*-review`) are read-only by
construction and must declare `tools:` without `Write`, `Edit` or `NotebookEdit`; `validate-skills.sh` enforces it.
Give any new agent that only reports findings the same treatment.

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
- [ ] `SKILL.md` is under ~12 KB (hard limit 16 KB), or its deep-dive sections are in `references/` with a reference map (§3b).
- [ ] Every `` `skill` §N `` citation resolves to a heading (the validator checks this).
- [ ] `templates/` files use only `{{placeholder}}` syntax.
- [ ] `docs/README.md` has a new row.
- [ ] Run `python3 tools/build-indexes.py` — it regenerates `docs/REGISTRY.md` (never edit that file by hand).
- [ ] `bash tools/validate-skills.sh` passes locally with zero errors.

## 6. Adding a brand-new skill (walkthrough)

```sh
SKILL=my-new-skill
P=ai-toolkit-java-design     # the plugin that owns the skill's phase
mkdir -p plugins/$P/skills/$SKILL
cat > plugins/$P/skills/$SKILL/SKILL.md <<'EOF'
---
name: my-new-skill
description: One paragraph explaining what this skill does. Use when <the situation that should trigger it>.
tier: should
applies_to: [rest]
depends_on: []
---

# My New Skill

## When to use
…

## 1. …
EOF

$EDITOR docs/README.md            # add a row to the skill index
python3 tools/build-indexes.py    # regenerates docs/REGISTRY.md and the other generated files

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

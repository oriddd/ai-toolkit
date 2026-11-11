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
    ├── agents/<agent>.md           ← agents (ai-toolkit-<lang>-agents; update-context lives in ai-toolkit-docs)
    └── hooks/                      ← optional (<lang>-design: language routing hook; workflow: neutral rules)
docs/                               ← README (skill index), REGISTRY, BACKEND_GUILD, LANGUAGE_CONTRACT,
                                      INDEX_BY_USE_CASE, AUTHORING, agents/
tools/                              ← build-indexes.py, validate-skills.sh, check-links.py, test-hooks.sh,
                                      check-versions.sh, check-repo-hygiene.sh
```

**Plugin boundary rule:** a plugin is installed on its own, so a `SKILL.md`
may link (`../other/SKILL.md`) only to skills in the *same* plugin. Refer to
skills in other plugins by name (`` `exception-handling` ``). The validator enforces this.

## 2. Frontmatter contract

Every `SKILL.md` **must** begin with YAML frontmatter, on line 1:

```yaml
---
name: <folder-name>          # REQUIRED — equals the parent directory name
description: <one-paragraph> # REQUIRED — ≤ 300 chars, says WHEN to use it ("Use when …"), names the language
tier: should                 # REQUIRED — lowercase: must | should | may | foundational
applies_to: [rest]           # project types (see LANGUAGE_CONTRACT.md for each language's shapes)
depends_on: []               # skills this one needs (the plugin must depend on their plugins)
ships_templates: false       # true when the skill has a templates/ folder (shown as "T" in REGISTRY.md)
hitl: false                  # true when the skill must ask the developer before it proceeds
version: 1.0
last_reviewed: 2026-11-03
---
```

All nine keys are expected in every skill; the validator fails on the rules below. Use `>` (folded) for a
long description; `tools/build-indexes.py` also reads `>-`, `|`, block lists and quoted values.

| Rule | Validator section |
| --- | --- |
| `name` field equals folder name | §2 |
| `description` present and says when to use it (`Use when …` / `Apply when …`) — in the description itself, not a later key | §2 |
| `description` ≤ 300 characters (the skill listing is budgeted; longer ones are cut) | §6d |
| `description` of a language skill names its language (Java / Spring / Maven, Python, React Native) | §6d |
| `tier` is one of must / should / may / foundational; every `depends_on` names an existing skill | §6d |
| Any markdown link `(./templates/<file>)` resolves | §3 |
| `docs/README.md` has a row naming the skill in backticks | §4, §6d |
| `REGISTRY.md` has a row for the skill (generated — run `build-indexes.py`) | §4 |
| `docs/INDEX_BY_USE_CASE.md` names the skill in backticks in at least one use-case row | §6d |
| Some routing table, agent or other skill references the skill (it is reachable) | §6d |
| `templates/` files use only `{{placeholder}}` syntax | §5 |
| Frontmatter parses as strict YAML (CI installs PyYAML) | §6e |

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
- [ ] `description:` is ≤ 300 characters, contains `Use when …` and names its language.
- [ ] `docs/README.md` has a new row, and `docs/INDEX_BY_USE_CASE.md` lists the skill under at least one use case.
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
$EDITOR docs/INDEX_BY_USE_CASE.md # name the skill (in backticks) in the use-case rows it serves
python3 tools/build-indexes.py    # regenerates docs/REGISTRY.md and the other generated files

bash tools/validate-skills.sh
```

## 7. Marking a skill experimental / deprecated

Add a banner immediately after the frontmatter:

```markdown
> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.
```

```markdown
> 🚨 **Deprecated since 2026-07-01.** Use `<replacement-skill>` instead.
```

Name the replacement in backticks. Link it (`../<replacement>/SKILL.md`) only when it is in the *same* plugin (§1).
The validator requires the Experimental banner on every Python and React Native skill and an `Experimental — `
prefix on those plugins' descriptions; the Deprecated banner is advisory.

## 8. Phases and languages

A plugin is one **phase** (workflow, docs, design, build, quality, ops, scaffold, agents), either
language-neutral (`ai-toolkit-workflow`) or per language (`ai-toolkit-<lang>-<phase>`). Put a skill in
the phase it belongs to — delivery workflow (commits, PRs, releases) never shares a plugin with
implementation (errors, validation) or testing. See [`LANGUAGE_CONTRACT.md`](./LANGUAGE_CONTRACT.md)
for naming, the required skills per language and the routing-hook convention.

## 9. Freshness policy

Skills pin real versions (Java 21, Spring Boot 3.5, Python 3.12, library majors), so they go stale. Every skill is
re-reviewed at least every **180 days**; `last_reviewed` records the date of the last review.

| Age of `last_reviewed` | Validator |
| --- | --- |
| ≤ 150 days | OK |
| 151–180 days | warning: due for review |
| > 180 days, or in the future | error: CI fails |

A review means, for each skill:

1. Check every pinned version and API against the upstream release notes (Spring Boot, Spring Framework, JDK, Maven
   plugins, Python / npm packages, GitHub Actions) and the standards it cites (RFCs, OWASP lists).
2. Fix what moved, keeping the skill's rules intact; record a behaviour change in `docs/CHANGELOG.md`.
3. Run the plugin's eval suite (§10) and the repo checks.
4. Set `last_reviewed` to today and bump the plugin version.

Only bump `last_reviewed` after an actual review — never in bulk to silence the validator. A new major version of a
pinned platform (for example Spring Boot 4) triggers a review of every skill that names it, whatever its date.
`FRESHNESS_MAX_DAYS` overrides the window for a local run only.

## 10. Evals

Each plugin with skills has a `claude plugin eval` suite under `evals/<plugin>/` (Claude Code ≥ 2.1.269). The suites
live at the repo root, not inside the plugin, because a case must load the plugin together with its `dependencies`
(`plugins: ["../../../plugins/<plugin>", …]`) and `claude plugin eval` only loads plugins below the directory it runs
against. A suite has three kinds of case:

- **Trigger cases** (`trigger-<skill>`): a realistic task phrased the way a developer would ask, with a `tool_used`
  grader asserting that the skill loaded. One per skill.
- **Behaviour cases** (`behaviour-<skill>`): the agent applies the skill to a small task; `regex` graders check the
  output for the skill's rules. Under the default with/without ablation the report shows the score with and without
  the plugin — the before/after evidence that the skill changes the agent's output.
- **Negative cases** (`no-trigger-*`): an unrelated request that must not load the plugin's skills.
- **Agent cases** (`delegate-<agent>`): a small project fixture (`fixture.sh`: a Spring Boot, FastAPI or React Native
  skeleton) and a request that names the agent, as documented in `docs/agents/CHEATSHEET.md`. Graders check that the
  main session starts the plugin agent and that the agent itself loads its key skill. `no-delegate-*` cases check that
  no agent starts for an unrelated question and that the main-session-only `scaffold-repo` is never run as a subagent.

```bash
bash tools/run-evals.sh                     # every trigger + negative case, 1 run, no baseline
bash tools/run-evals.sh behaviour           # behaviour cases, 3 runs, with/without-plugin baseline
bash tools/run-evals.sh agents              # agent cases (runs the fixture scripts, grants the Agent tool)
claude plugin eval . --eval-dir evals --case 'trigger-persistence' --runs 1 --ablation none --trust-plugin   # one case
```

The case files are generated: edit the prompts and graders in `tools/eval_cases/` (`triggers.py`, `behaviour.py`,
`agents.py`) and run `python3 tools/build-evals.py`; CI runs it with `--check`. `tools/validate-skills.sh` fails when a skill has no trigger case, the case does not load the skill's plugin, or an
agent has no agent case. Add
the trigger case in the same PR as the skill. Evals cost API credits, so CI does not run them: run them before a
release and after any change to a skill's `description`, and record the pass rate in `docs/CHANGELOG.md`.


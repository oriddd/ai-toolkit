# Toolkit Cheatsheet

The 30-second overview of what lives where and how to use it.
For deep-dives, follow the links — each area has its own cheatsheet next to it.

---

## Where things live

```
.claude-plugin/marketplace.json   → the marketplace
plugins/
├── ai-toolkit-workflow/        → commits, PR descriptions, releases, parallel delegation   (any stack)
├── ai-toolkit-docs/            → ADRs, UML, context templates                              (any stack)
├── ai-toolkit-quality/         → completion gate, code hygiene, Sonar gate                 (any stack)
├── ai-toolkit-<lang>-design/   → structure, patterns, conventions  (+ language routing hook)
├── ai-toolkit-<lang>-build/    → errors, validation, persistence, security, integrations
├── ai-toolkit-<lang>-quality/  → tests, static analysis, review
├── ai-toolkit-<lang>-ops/      → CI/CD, observability
├── ai-toolkit-<lang>-agents/   → task agents: new endpoint/screen/feature, refactor, code-review, test-writer
└── ai-toolkit-java-scaffold/   → repo scaffolder (Java)
docs/    → indexes, guild rules, LANGUAGE_CONTRACT      tools/ → validators and index builder
```

`<lang>` = `java` · `python` · `react-native`.

---

## Install

```
/plugin marketplace add <git-url-or-path-to-this-repo>
/plugin install ai-toolkit-workflow@ai-toolkit
/plugin install ai-toolkit-python-design@ai-toolkit      # pick your language
```

The `*-design` plugin's SessionStart hook injects task→skill routing only for projects of that
language. Installing a `-design` plugin already pulls in that language's `-build`, `-quality` and `-ops`; each `<lang>-agents` plugin depends on the design plugin.

---

## Use it in your project (JetBrains + GitHub Copilot — see setup/jetbrains/)

```bash
# once: symlink the toolkit globally
ln -s /path/to/ai-toolkit ~/.ai-toolkit
```

Then in any Copilot chat — load only what you need, when you need it:

```
# a single skill
#file ~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/exception-handling/SKILL.md

# a task agent
#file ~/.ai-toolkit/plugins/ai-toolkit-java-agents/agents/new-endpoint.md
```

Full setup: [`../setup/jetbrains/README.md`](../setup/jetbrains/README.md).

---

## Find the right thing

| I want to… | Go to |
| --- | --- |
| See every skill at a glance | [`docs/REGISTRY.md`](REGISTRY.md) |
| Find skills for a task | [`docs/INDEX_BY_USE_CASE.md`](INDEX_BY_USE_CASE.md) |
| Know what's mandatory | [`docs/BACKEND_GUILD.md`](BACKEND_GUILD.md) |
| Pick a task agent | [`docs/agents/README.md`](agents/README.md) |
| Author a skill | [`docs/AUTHORING.md`](AUTHORING.md) + [`docs/SKILLS_CHEATSHEET.md`](./SKILLS_CHEATSHEET.md) |
| Author an agent | [`docs/agents/CHEATSHEET.md`](agents/CHEATSHEET.md) |
| Bootstrap project docs | [`context/`](../plugins/ai-toolkit-docs/skills/context-maintenance/templates/context/README.md) |

---

## Validate everything

```bash
bash tools/validate-skills.sh      # all skills lint clean
python3 tools/build-indexes.py --check   # indexes in sync
bash plugins/ai-toolkit-docs/skills/context-maintenance/templates/context/validate-context.sh           # context templates valid
```


# Language Contract

Plugins are organised on two axes: **phase** and **language**.

| Kind | Name | Holds |
| --- | --- | --- |
| Neutral | `ai-toolkit-workflow` | commits, PRs, releases, parallel delegation — any stack |
| Neutral | `ai-toolkit-docs` | ADRs, diagrams, context templates — any stack |
| Neutral | `ai-toolkit-quality` | definition of done: `completion-gate`, `code-hygiene`, `sonar-quality-gate` — any stack |
| Per language | `ai-toolkit-<lang>-design` | project/package structure, architecture patterns, conventions. **Ships the routing hook.** |
| Per language | `ai-toolkit-<lang>-build` | implementation concerns: errors, validation, persistence, security, integrations |
| Per language | `ai-toolkit-<lang>-quality` | tests, static analysis, quality review |
| Per language | `ai-toolkit-<lang>-ops` | CI/CD, observability, release/runtime |
| Per language | `ai-toolkit-<lang>-agents` | optional task agents |

A skill belongs to exactly one phase. Never mix delivery workflow with implementation or testing.

## Definition of done

`completion-gate` is the single definition of done for every language. Each language's `quality` plugin
supplies the concrete commands (build, tests, static analysis, coverage) that the gate's command table points to —
when you add a language, add its row there. Nobody commits until the developer asks; `ai-toolkit-workflow` backs that with a best-effort hook (a safety net, not a guarantee).

## Skill naming

Java is the original set and keeps unprefixed names (`code-structure`). Every other language
prefixes its skills with the language slug (`python-code-structure`, `react-native-code-structure`)
so a routing table entry names exactly one skill.

## Agents

Agents follow the skill naming rule: Java unprefixed (`test-writer`), others `<slug>-<agent>`
(`python-test-writer`, `react-native-code-review`). A language's agents plugin provides at least a code-review
agent (read-only, applies `code-hygiene`), a test-writer worker, and one agent per code-writing task shape
(endpoint / screen / feature / refactor). Code-writing agents must carry the commit policy and run
`completion-gate`; `update-context` is the one neutral agent (in `ai-toolkit-docs`).

## Required skills for a language

A language is **complete** when it provides these concerns (names are `<slug>-<concern>`):

| Phase plugin | Required concerns |
| --- | --- |
| design | `code-structure` |
| build | `error-handling` (Java: `exception-handling`), `input-validation` |
| quality | `unit-tests`, `static-analysis` |
| ops | `ci` |

Languages marked **draft** (marked "(draft)" in the plugin description) may provide only these;
everything else is optional and added as the standards mature.

## Routing hook

The `design` plugin ships `hooks/hooks.json` (SessionStart) and `hooks/detect-and-route.sh`, which
prints `hooks/routing.md` **only when the project is that language**:

| Language | Detect |
| --- | --- |
| Java | `pom.xml`, `build.gradle(.kts)`, `settings.gradle(.kts)` |
| Python | `pyproject.toml`, `requirements*.txt`, `setup.py`, `setup.cfg`, `Pipfile` |
| React Native | `package.json` containing `"react-native"` |

`routing.md` is a task → skill table plus 3–4 gates, under ~350 tokens.

## SKILL.md frontmatter

Same as `AUTHORING.md`; `applies_to` uses the language's project shapes (Java: `rest`, `event`, …;
Python: `rest`, `worker`, `cli`, `library`; React Native: `mobile`).

## Dependencies and installation

Plugins declare `dependencies` in `plugin.json` (bare names, same marketplace; Claude Code installs them with the plugin).
The graph must stay acyclic and shallow:

- A plugin depends on **every plugin its skills' `depends_on` name** and nothing more; the validator fails a missing dependency and any cycle.
  So `-design` depends only on the neutral `ai-toolkit-quality` (its routing table cites `completion-gate`), `-quality` on `-design` (Python / React Native also `-build`), `-ops` on `-design` and `-quality`, and
  `-build` on what its skills need (Java: design, ops, quality, workflow). A skill never lists a skill from a *later* phase in `depends_on`;
  mention it in prose instead.
- `ai-toolkit-<lang>` (java, python, react-native) is a manifest-only plugin that depends on that language's four phase plugins and
  `ai-toolkit-workflow` (Java also `ai-toolkit-docs`) — installing it is installing the language.
- `ai-toolkit-<lang>-agents` depends on that language's four phase plugins and `ai-toolkit-docs` (Java also `ai-toolkit-java-scaffold`).
- `ai-toolkit-docs` depends on `ai-toolkit-workflow`, which depends on `ai-toolkit-quality`, which depends on nothing.
- References between skills of different plugins are by **name** only (never relative links) — the validator enforces it.

## Names, routing and agents at runtime

- Plugin skills and agents are namespaced `plugin:name`. Java skills, the neutral skills (`completion-gate`, `code-hygiene`,
  `parallel-delegation`, …) and every sibling agent are referred to in the qualified form
  (`ai-toolkit-java-design:code-structure`, `ai-toolkit-quality:completion-gate`, `ai-toolkit-java-agents:test-writer`) because a
  bare name can resolve to a stale user-level copy and the Agent tool does not resolve bare plugin agent names.
  `python-*` and `react-native-*` skills carry a unique prefix, so those names may stay bare.
- Every routing table stays under 400 words (injected every session) and names only existing skills; a Java row carries its
  phase letter, e.g. `code-structure` (d). Validated by `tools/validate-skills.sh`.
- Skill descriptions are capped at 600 characters, must contain a `Use when` trigger and must name their language
  (Java: Java / Spring / Maven; Python; React Native).
- Plugins are cached by `version` — bump it when a plugin's content changes (`tools/check-versions.sh`, enforced in CI).

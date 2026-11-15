---
name: documentation-and-adr
description: >
  Docs as code for any language — README, CONTRIBUTING, ARCHITECTURE with C4 diagrams (hand-written Mermaid by
  default, PlantUML/Structurizr optional), ADRs under docs/adr/, per-use-case sequence diagrams. Use when a repo is
  created or a non-trivial design choice is made.
tier: must
applies_to: [rest, event, scheduler, library, monolith, worker, cli, mobile]
depends_on: [uml-diagram]
ships_templates: false
hitl: false
version: 1.1
last_reviewed: 2026-11-15
---

# Documentation & ADRs Skill
Living documentation, kept under version control, checked by CI. The rules apply to every language; where a rule
points at a language skill, use the one for your stack:

| Concern | Java | Python | React Native |
| --- | --- | --- | --- |
| Repo scaffold (README, CONTRIBUTING) | `create-repo` | — | — |
| Local dev and verify commands | `local-dev-experience` | `python-static-analysis` §5 | `react-native-static-analysis` §1 |
| Tests | `unit-tests`, `component-tests`, `integration-tests` | `python-unit-tests`, `python-integration-tests` | `react-native-unit-tests`, `react-native-e2e-tests` |
| Format / lint gate | `static-analysis` | `python-static-analysis` | `react-native-static-analysis` |
| API contract | `openapi-first-codegen` / springdoc | FastAPI's generated `/openapi.json` | — |
| SLIs / SLOs | `observability` §4 | `python-observability` §5 | `react-native-observability` §7 |
| Review checklist | `quality-review` | `python-code-review` agent | `react-native-code-review` agent |

## 1. `README.md` (Java: produced by `create-repo`)

Must answer in under 60 seconds:
1. What the service does (one paragraph).
2. How to run it locally (`make up && make run`).
3. Where the API contract lives (link to the OpenAPI document, generated or hand-written — see the table above).
4. Where the architecture overview lives (link to `docs/ARCHITECTURE.md`).
5. Where ADRs live (link to `docs/adr/`).
6. Codeowner.

## 2. `CONTRIBUTING.md`

- How to set up the dev env (refers to the language's local-dev skill — table above).
- Branching + commit-message convention (refers to `git-commit-conventions`; release tags and CHANGELOG in `release-versioning`).
- Test policy (refers to the language's test skills — table above).
- Definition of Done — every PR checks: tests pass, formatter clean, no new high-severity static-analysis finding
  (Java: Spotless clean, no new SpotBugs HIGH), OpenAPI snapshot reviewed, ADR added if architectural
  (`completion-gate` is the full list).
- Review SLA.

## 3. `docs/ARCHITECTURE.md` + C4 diagrams

Three C4 levels are sufficient:

```
docs/
├── ARCHITECTURE.md
└── diagrams/
    ├── c4-context.md        # mermaid — who calls this service, what does it call
    ├── c4-container.md      # mermaid — processes (the service, DB, broker, …)
    └── c4-component.md      # mermaid — internal packages, usually drawn from the module-boundary rules
                             # (Java: ArchUnit slices; Python: import-linter; RN: eslint boundaries — see the code-structure skill)
```

When the repo keeps a `context/` folder (`context-maintenance`), the C4 context and component diagrams live there
(`context/system-context.md`, `context/component-diagram.md`) and `docs/ARCHITECTURE.md` links to them instead of
`docs/diagrams/c4-*.md` — one copy of each diagram, never two.

Default to **Mermaid** — fenced `mermaid` blocks in `.md` files render natively on GitHub / GitLab, so there is nothing to render or commit
(see [`uml-diagram`](../uml-diagram/SKILL.md)). Use **Structurizr DSL** or **C4-PlantUML** (`c4-*.puml` in the same folder) only when you
need C4 tooling; then render in CI:

```yaml
# pinned PlantUML image — pin the tag (or digest), never :latest
- run: docker run --rm -v "$PWD:/work" -w /work plantuml/plantuml:<pinned-version> -tsvg -o _rendered docs/diagrams/*.puml
- run: test -z "$(git status --porcelain docs/diagrams/_rendered)"   # fails when an SVG is stale or new and uncommitted
```

With PlantUML / Structurizr, generated SVGs are committed to `docs/diagrams/_rendered/`; pre-commit
fails if `.puml` changed but the SVG was not regenerated:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: plantuml-rendered
        name: PlantUML SVGs are up to date
        language: system
        files: ^docs/diagrams/.*\.puml$
        pass_filenames: false
        entry: bash -c 'docker run --rm -v "$PWD:/work" -w /work plantuml/plantuml:<pinned-version> -tsvg -o _rendered docs/diagrams/*.puml && test -z "$(git status --porcelain docs/diagrams/_rendered)"'
```

Mermaid diagrams need neither step.

## 4. `docs/adr/` — Architecture Decision Records

Capture *why*, not *what*. One file per decision, immutable once accepted (the only later edit is the `Status`
line when it is superseded).

File name: `docs/adr/NNNN-<kebab-case-slug>.md`, numbered in sequence (e.g. `docs/adr/0007-use-kafka-for-events.md`);
the title inside is `ADR-NNNN — <Title>`. Template — copy it to `docs/adr/template.md` when the repo is created:

```markdown
# ADR-NNNN — <Title>

* Status: PROPOSED | ACCEPTED | DEPRECATED | SUPERSEDED by ADR-MMMM
* Date: YYYY-MM-DD
* Deciders: @alice @bob
* Tags: persistence, security, …

## Context
What problem are we solving? What forces are at play?

## Decision
What we chose.

## Consequences
Positive, negative, neutral.

## Alternatives considered
A, B, C — each with one paragraph on why not.
```

When to write an ADR:
- Choosing one technology over another (Kafka vs RabbitMQ, JPA vs jOOQ, ORM vs query builder).
- Introducing a new cross-cutting pattern.
- Choosing a wire format.
- Disabling a security default.
- Deviating from a toolkit skill.

ADRs are **append-only**. Superseding an old ADR creates a new one; the old ADR's `Status` line is changed to
`SUPERSEDED by ADR-MMMM` and nothing else in it.

## 5. `docs/SLO.md`

The SLI/SLO table for the service — how to define it is in the language's observability skill (table above).
Services only; a library or CLI without a runtime contract has no `docs/SLO.md`.

## 6. Use-case diagrams

Written by hand from the entry point (controller, route handler, screen) and the use-case code it calls — OpenAPI
tooling documents the API contract, it does not draw sequence diagrams. Mermaid by default (`uml-diagram`); `.puml`
only when the repo already uses PlantUML:

```
docs/diagrams/
├── usecase-create-invoice.md       # mermaid flowchart
├── sequence-export-invoice.md      # mermaid sequenceDiagram
└── …
```

For each public endpoint (or user-facing flow), ship one sequence diagram and one use-case diagram. They live in
`docs/diagrams/` — the one diagram location — and are updated in the same PR as the use case and its test.

## 7. Generated docs index

`docs/README.md` lists every doc with a one-line summary so a newcomer can
navigate without `grep`.

## Do / Don't

✅ Documentation is code: lives in the repo, is reviewed in PR, is rendered
in CI.
✅ Every architectural choice has an ADR.
✅ Diagrams are text-first (Mermaid by default; PlantUML / Structurizr when needed) so they diff in git.
❌ Never put architecture diagrams in Confluence or a slide deck "as the
source of truth" — they drift the day after the meeting.
❌ Never amend a past ADR; supersede it (only its `Status` line changes).


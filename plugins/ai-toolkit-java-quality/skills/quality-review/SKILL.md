---
name: quality-review
description: >
  Java / Spring Boot code review of a class, package or PR — SOLID, clean code, LEGO-brick packaging, testability
  anti-patterns, exception/logging/concurrency conventions, test quality and coverage — with concrete fixes. Use
  before opening a PR or when refactoring legacy code.
tier: must
applies_to: [rest, event, scheduler, library, monolith]
depends_on: [unit-tests, static-analysis, testable-code-principles]
ships_templates: false
hitl: false
version: 1.1
last_reviewed: 2026-07-12
---

# this Quality Review Skill

This skill performs a structured, evidence-based review of Java code against
the project conventions. The output is a **report**, not a refactor — the
developer accepts/rejects each finding and applies fixes (optionally via the
other skills).

## When to invoke

- Before opening a PR (run on the diff).
- When onboarding a legacy class to project conventions.
- During design review of a new package.

## Inputs

- A class, a package, or a list of changed files.
- Optionally: the test class(es) for the code under review.

## Review checklist (run **every** item; report PASS / FAIL / N/A + evidence)

Full review: read **every** file below, in order — do not skip a category. Load a single file only for a scoped review.

| Sections | Topic | Load when | File |
| --- | --- | --- | --- |
| A, B | SOLID and package structure checks | **every full review** | [`solid-and-packaging.md`](./references/solid-and-packaging.md) |
| C | exceptions, logging, concurrency, conventions | **every full review** | [`conventions.md`](./references/conventions.md) |
| D, E, F | test meaningfulness, testability anti-patterns, quantitative limits | **every full review** | [`tests-antipatterns-thresholds.md`](./references/tests-antipatterns-thresholds.md) |

## Do / Don't

✅ Cite **line numbers / class names** as evidence for every finding.
✅ Reference the canonical pattern by skill name so the developer knows where
to look for the template.
✅ When unsure, mark `WARN` not `FAIL`; ambiguity is the reviewer's problem.
❌ Never edit code in this skill — produce a report; the developer applies
fixes via the dedicated skill.
❌ Never report on issues that the parent BOM, ResponseEntityExceptionHandler, or
the Spring Boot starters already solve.
- `code-hygiene`, `completion-gate` — the language-neutral hygiene check and definition of done that run alongside this review.

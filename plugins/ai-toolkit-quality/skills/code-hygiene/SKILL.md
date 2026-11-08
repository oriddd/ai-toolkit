---
name: code-hygiene
description: >
  Keep a diff minimal and self-explanatory — no comments restating code, no dead code, no speculative abstraction, no
  unrelated churn, no redundant tests. Use when reviewing your own diff before saying done, and before adding a
  comment, docstring or test.
tier: must
applies_to: [rest, event, scheduler, library, monolith, worker, cli, mobile]
depends_on: []
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

# Code Hygiene Skill
## When to use

Before you call a change done, read your own diff with this skill. Names document the code; every
extra line must earn its place.

## 1. Comments and API docs

Write a comment or doc block only when it says something the code cannot:

- ✅ **Why** — a constraint, workaround (with ticket), invariant, ordering requirement, or a non-obvious trade-off.
- ✅ A **public contract** of a library/SDK that consumers read (semantics, thread-safety, errors) — not internal code.
- ❌ Restating the name or signature: `/** Gets the id. */`, `// increment i`, `@param id the id`, `@return the result`.
- ❌ Docs on private members, overrides, getters, records, tests, or one-line obvious methods.
- ❌ `@author`, change history, section banners, ASCII art, closing-brace comments.
- ❌ Commented-out code (version control remembers), `TODO` without an owner or ticket.

If you feel the urge to explain *what* a block does, rename or extract instead.
When a comment is needed, one sentence. Match the surrounding code's density.

## 2. Redundant and meaningless tests

Coverage is a signal, not the goal. Remove or merge a test when it:

| Smell | Do instead |
| --- | --- |
| Same branch as another test with different data | One parameterised test |
| Tests a getter, setter, record, `toString`, Lombok output | Delete — it tests the language |
| Tests framework or library behaviour (Spring wiring, ORM, JSON lib) | Delete; keep one wiring test at the real boundary |
| Only verifies mocks were called, asserts no outcome | Assert the observable result |
| Asserts what the stub was told to return | Delete — it cannot fail |
| No assertion, or asserts `notNull` / `true` only | Assert the behaviour or delete |
| Re-tests at unit level exactly what a component/integration test already pins | Keep the lower-cost one |
| Reaches into private methods or internal state | Test through the public behaviour |

Keep a test when removing the behaviour it pins would make it fail. Every new or changed branch needs
such a test; every other test must justify itself the same way.

## 3. Dead and speculative code

- No unused imports, parameters, fields, methods, classes, config keys or dependencies you introduced.
- No abstraction for a second implementation that does not exist (see `pattern-selection` (Java; the principle applies to every language): smallest pattern that fits).
- No flags, hooks or generic parameters "for later".
- No catch-and-ignore, no swallowed exceptions, no leftover `printStackTrace` / `print` / `console.log`.

## 4. Diff discipline

- The diff contains only what the task needs. No drive-by renames, reformatting of untouched files,
  import reordering or unrelated fixes — mention them instead.
- New dependency? Justify it or remove it.
- Generated files, build output, local config and secrets are never part of the diff.

## 5. Self-review procedure

1. `git diff` (and `git status` for untracked files) — read every hunk as a reviewer.
2. Scan added lines for the comment, test and dead-code smells above; grep the diff for
   `TODO|FIXME|println|printStackTrace|console\.log|print\(|@Disabled|\.skip\(|noqa|eslint-disable|SuppressWarnings`.
3. For each new test ask: which behaviour change would make it fail? None → delete or fix.
4. Fix, then return to the `completion-gate` build step.

## Anti-patterns

- ❌ Javadoc/docstring on every method "for completeness".
- ❌ A test per getter to hit a coverage number.
- ❌ Keeping a redundant test "just in case".
- ✅ Small diff, self-explanatory names, each test pins a behaviour.

## Cross-references

`completion-gate`, and per language its testability, unit-test and review skills (Java `testable-code-principles`, `unit-tests`, `quality-review`; `python-unit-tests`, `python-static-analysis`; `react-native-unit-tests`, `react-native-static-analysis`).

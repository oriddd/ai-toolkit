---
name: react-native-new-screen
description: Add a standards-compliant screen to an existing React Native (TypeScript) app — typed navigation route, screen, hook, api/query, validation schema, error handling and tests. Use when the developer asks for a new screen or page-level flow.
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# Agent: New React Native Screen

> **Purpose:** Add a standards-compliant screen to an existing React Native
> app, from route to tests.

You are a mobile-coding agent for a React Native / TypeScript (strict) app. The developer wants a
**new screen**. You produce every change needed to satisfy the guild standards.

## Skills to apply (in this order)

Load each skill with the Skill tool, by its qualified name, first — before any CLARIFY question or code — do not work from memory. Also
load `ai-toolkit-quality:completion-gate` and `ai-toolkit-quality:code-hygiene` before you finish (see the gate below).

1. `ai-toolkit-react-native-design:react-native-code-structure` — feature folder, dependency direction, typed navigation, naming;
   screens stay thin and delegate to hooks.
2. `ai-toolkit-react-native-design:react-native-state-and-data` — feature api module, query-key factory, query hook returning what
   the screen needs; Zustand only for genuinely client-side state.
3. `ai-toolkit-react-native-build:react-native-input-validation` — zod schema in the validation layer, react-hook-form wiring,
   server-side validation errors mapped to fields.
4. `ai-toolkit-react-native-build:react-native-error-handling` — errors mapped to `AppError` in one place, message catalogue,
   error boundary / inline error state.
5. `ai-toolkit-react-native-build:react-native-security` — only if the screen handles tokens, deep links or sensitive data.
6. `ai-toolkit-react-native-ops:react-native-observability` — screen-view analytics via the analytics interface, no PII.
7. `ai-toolkit-react-native-quality:react-native-unit-tests` — component, hook, schema and mapper tests.
8. `ai-toolkit-react-native-quality:react-native-e2e-tests` — only if the screen is on a critical user journey; add stable test IDs.
9. `ai-toolkit-react-native-quality:react-native-static-analysis` — keep the repo's lint/type/format rules satisfied.

## Step-by-step procedure

```
1. CLARIFY (only if missing):
   - Screen purpose, entry points, route params
   - Data it reads/writes (endpoints, shapes) and loading/empty/error states
   - Form fields and rules, if any
   - Auth requirement

2. DESIGN: place the screen in its feature folder; add the route to the typed
   navigation param list. Surface conflicts with existing routes.

3. GENERATE (in order):
   a. Route type + registration in the navigator (typed params, no `any`).
   b. Feature api function + query-key factory entry + query/mutation hook.
   c. Validation schema (zod) + message catalogue entries, if the screen has input.
   d. Screen-level hook holding the logic; the screen component only renders.
   e. Screen component — loading, empty, error and success states; test IDs on
      interactive elements.
   f. AppError mapping / catalogue entry if a new error case is introduced.
   g. Analytics screen-view event through the analytics interface, if required.

4. TEST:
   a. Unit tests: hook, schema, mapper, component (RNTL, MSW for network).
   b. E2E flow only when the screen is on a critical journey.

5. CONTEXT:
   - Update the architecture/context docs if a new capability is exposed.
   - Append to CHANGELOG.md [Unreleased] — only when no release bot (release-please / semantic-release) owns it; with a bot, the Conventional Commit message is the changelog entry.
```

## Questions when you run as a subagent

A subagent cannot ask the developer — only the main session can. If a CLARIFY / ASK question or a confirmation
step is still open and your brief does not answer it, write no files: return `NEEDS INPUT:` with the numbered
questions and the default you would assume for each, then stop. The caller asks the developer in the main session
and invokes you again with the answers. Never invent the answer to a HITL question.

## Delegation (use subagents when you can)

Follow the `ai-toolkit-workflow:parallel-delegation` skill. Delegate as below whenever the Agent tool is available —
also when you run as a subagent yourself (a subagent can start subagents); if it is not available, do the same
steps inline, in order.

1. **Sequential (you):** design, route, api module, query hook, schema, screen hook and component.
2. **Parallel fan-out, one message:**
   - `ai-toolkit-react-native-agents:react-native-test-writer` — tests for the hook, schema and mapper;
   - `ai-toolkit-react-native-agents:react-native-test-writer` — component tests for the screen (all states);
   - `ai-toolkit-docs:update-context` — architecture note + CHANGELOG `[Unreleased]` (only when no release bot owns it).
3. **Sequential (you):** run `npm run verify`, then `ai-toolkit-react-native-agents:react-native-code-review` on the diff and fix blockers.

Every subagent brief must say that the subagent does **not** run builds or the test suite (the main thread owns
them), unless you explicitly write "run your own tests" in a test-writer brief, and that it never stages, commits,
pushes or stashes. Shared test infrastructure (MSW `handlers.ts`, the jest setup file, shared test utilities) stays
with you: add the handlers and fixtures the tests need before the fan-out.

Keep shared files (`package.json`, navigator, tsconfig, lint config, message catalogue) and the
verify run to yourself. Verify every result (read the diff, run the tests) before reporting done.

## Commit policy and completion gate

Never `git commit`, `git push`, `git stash` or tag — leave the changes in the working tree until the developer asks.
Before reporting the task done, run the `ai-toolkit-quality:completion-gate` skill — all nine checks — (the verify script `npm run verify` = `tsc --noEmit && eslint . --max-warnings 0 && prettier --check . && jest --ci --coverage`, see
`ai-toolkit-react-native-quality:react-native-static-analysis`; coverage of the changed files; `ai-toolkit-quality:code-hygiene`; Sonar) and finish with its evidence
table. Fix failures at the cause; never suppress or weaken a check (`eslint-disable`, `@ts-ignore`,
`it.skip`, lowered thresholds) to get green. Return the evidence table to your caller unchanged, so it can relay it
instead of running the gate again.
Gate check 5 (Standards) is the `ai-toolkit-react-native-agents:react-native-code-review` run from the delegation plan above: reuse its report as the
evidence instead of reviewing a second time; re-run it only if you changed code after it. Without the Agent tool,
run check 5 inline: apply the Do/Don't lists of the loaded `react-native-*` skills to the whole diff, including untracked files.

## Checklist before returning

- [ ] Route is typed; no `any` or `@ts-ignore`.
- [ ] Screen contains no data fetching or business logic; the hook owns it.
- [ ] Server state in TanStack Query behind the feature api module; keys from the factory.
- [ ] Input validated with a zod schema; messages from the catalogue.
- [ ] Errors mapped to `AppError` in one place; loading, empty and error states rendered.
- [ ] No secrets, tokens or PII in code or logs.
- [ ] Tests cover happy path, error path and edge cases; queries are behaviour-focused.
- [ ] CHANGELOG updated — only when no release bot owns it (`ai-toolkit-workflow:release-versioning`).
- [ ] `ai-toolkit-quality:completion-gate` evidence table produced; nothing committed.

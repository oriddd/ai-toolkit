## ai-toolkit React Native standards (MANDATORY routing)

Standards are only applied if the skill is LOADED first. Do not write code from memory. Load with the Skill tool using the
qualified name `ai-toolkit-react-native-<phase>:<skill>`, phase d=design, b=build, q=quality, o=ops (bare names can resolve to
stale copies).

**Before writing or editing React Native code — and before asking clarifying questions — load the skills for the task:**

| Task | Load first |
| --- | --- |
| New screen / component / hook / folder, accessibility, lists | `react-native-code-structure` (d) |
| Fetching, caching, mutations, global state | `react-native-state-and-data` (d) |
| Throwing / mapping / displaying errors | `react-native-error-handling` (b) |
| Form or any input rule | `react-native-input-validation` (b) |
| Tokens, storage, deep links, logging | `react-native-security` (b) |
| New or changed test | `react-native-unit-tests` (q) (+ `react-native-e2e-tests` (q) for flows) |
| Lint / tsc / hooks config | `react-native-static-analysis` (q) |
| Pipeline, builds, releases | `react-native-ci` (o) |
| Crash reporting, analytics, logs | `react-native-observability` (o) |

**React Native gates**
1. Prefer the smallest pattern that fits; do not over-engineer.
2. Before saying done, run `ai-toolkit-quality:completion-gate`: the verify script (`npm run verify` = `tsc --noEmit && eslint . --max-warnings 0 && prettier --check . && jest --ci --coverage`, see `react-native-static-analysis` (q)) must pass; a failing check means the standard was not applied. Never commit unless asked.
3. Components render state from hooks: no fetching or business rules inside them.

Postman skills apply only to Postman collections or workspaces — code standards come from this table.

`CLAUDE.md` overrides skill defaults.

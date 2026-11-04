## ai-toolkit React Native standards (MANDATORY routing)

Standards are only applied if the skill is LOADED first. Do not write code from memory.

**Before writing or editing React Native code, load the skills for the task:**

| Task | Load first |
| --- | --- |
| New screen / component / hook / folder | `react-native-code-structure` |
| Fetching, caching, mutations, global state | `react-native-state-and-data` |
| Throwing / mapping / displaying errors | `react-native-error-handling` |
| Form or any input rule | `react-native-input-validation` |
| Tokens, storage, deep links, logging | `react-native-security` |
| New or changed test | `react-native-unit-tests` (+ `react-native-e2e-tests` for flows) |
| Lint / tsc / hooks config | `react-native-static-analysis` |
| Pipeline, builds, releases | `react-native-ci` |
| Crash reporting, analytics, logs | `react-native-observability` |

**React Native gates**
1. Prefer the smallest pattern that fits; do not over-engineer.
2. Before saying done, run `ai-toolkit-quality:completion-gate`: the verify script (`npm run verify` = `tsc --noEmit && eslint . --max-warnings 0 && prettier --check . && jest --ci --coverage`, see `react-native-static-analysis`) must pass; a failing check means the standard was not applied. Never commit unless asked.
3. Components render state from hooks: no fetching or business rules inside them.

Postman skills apply only to Postman collections or workspaces — code standards come from this table.

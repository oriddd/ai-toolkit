---
name: react-native-static-analysis
description: >
  React Native static analysis — TypeScript strict, ESLint flat config, Prettier, boundary rules, lint-staged and
  husky, all breaking the CI build. Use when bootstrapping a repo, changing lint or tsc config, or fixing a violation.
tier: must
applies_to: [mobile]
depends_on: [react-native-code-structure]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-15
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# React Native Static Analysis Skill
## When to use

Use when creating a repo, adding a rule, or when a check fails. Static analysis is
**non-skippable**: the same commands run locally, in the pre-commit hook and in CI, and any violation
fails the build. Never silence a rule to make a PR green.

**The verify script** is `npm run verify` = `tsc --noEmit && eslint . --max-warnings 0 && prettier --check . && jest --ci --coverage`
(wired in section 1). It is the single completion gate for developers, agents, the `completion-gate` skill and CI.

## Layout

```
eslint.config.mjs
.prettierrc.json
.prettierignore            # generated output: coverage, dist, ios, android, .expo
tsconfig.json              # strict, see react-native-code-structure
babel.config.js            # module-resolver aliases that Metro and Jest need (react-native-code-structure, references/expo-template-setup.md)
jest.config.js  jest.setup.ts   # react-native-unit-tests
.husky/pre-commit
package.json               # scripts + lint-staged
```

## Dependencies

```json
{ "devDependencies": { "typescript": ">=5.6 <6.1", "eslint": "^10.0.0", "typescript-eslint": "^8.72.0",
  "eslint-plugin-react-hooks": "^7.1.0", "eslint-plugin-boundaries": "^7.4.0",
  "eslint-import-resolver-typescript": "^4.4.0",
  "eslint-plugin-testing-library": "^7.16.0", "eslint-plugin-jest": "^29.0.0", "eslint-config-prettier": "^10.1.0",
  "prettier": "^3.3.0", "husky": "^9.1.0", "lint-staged": "^17.0.0" } }
```

These ranges were installed together on ESLint 10 with no peer-dependency conflict. ESLint 9 is end of life (npm marks
9.39.x "no longer supported"). Do not add `eslint-plugin-react-native`: its last release (5.0.0, December 2024) peers on
ESLint <= 9; its one rule used here, `no-inline-styles`, is a core `no-restricted-syntax` selector in section 2.
`typescript-eslint` supports TypeScript below 6.1, so use TypeScript 5.x or 6.0 (whichever your Expo SDK ships, SDK 58:
`~6.0`), never TypeScript 7. `lint-staged` 17 needs Node >= 22.22.1 (see `.nvmrc` in `react-native-ci`).

## 1. Scripts: the single source of truth

```json
{ "scripts": {
  "typecheck": "tsc --noEmit",
  "lint": "eslint . --max-warnings 0",
  "format:check": "prettier --check .",
  "test": "jest --ci --coverage",
  "verify": "tsc --noEmit && eslint . --max-warnings 0 && prettier --check . && jest --ci --coverage",
  "prepare": "husky"
} }
```

`verify` is the verify script, `tsc --noEmit && eslint . --max-warnings 0 && prettier --check . && jest --ci --coverage`,
in that order, stopping at the first failure. `--max-warnings 0` makes warnings fail; there is no "warn" tier.
`prepare` installs the husky hooks on `npm install`.

## 2. ESLint flat config

```js
// eslint.config.mjs
import { defineConfig } from 'eslint/config';     // replaces the deprecated tseslint.config()
import tseslint from 'typescript-eslint';
import reactHooks from 'eslint-plugin-react-hooks';
import boundaries from 'eslint-plugin-boundaries';
import testingLibrary from 'eslint-plugin-testing-library';
import jest from 'eslint-plugin-jest';
import prettier from 'eslint-config-prettier';

// inside a feature: screens -> components/hooks -> api -> model, never upward, never into another feature's layers
const LAYERS = { screens: ['screens', 'components', 'hooks', 'model'], components: ['components', 'model'],
  hooks: ['hooks', 'api', 'model'], api: ['api', 'model'], model: ['model'] };
const sameFeature = (types) =>
  ({ to: { element: { types, captured: { feature: '{{ from.element.captured.feature }}' } } } });
const ALL = ['routes', 'bootstrap', 'feature', ...Object.keys(LAYERS)];

export default defineConfig(
  { ignores: ['node_modules', 'ios', 'android', 'coverage', 'dist', '.expo'] },
  tseslint.configs.strictTypeChecked,
  { languageOptions: { parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname } } },
  {
    linterOptions: { reportUnusedDisableDirectives: 'error' },
    plugins: { 'react-hooks': reactHooks, boundaries },
    settings: {
      // without this resolver the @bootstrap/* @features/* @shared/* aliases do not resolve and boundaries checks nothing
      'import/resolver': { typescript: { project: './tsconfig.json' } },
      'boundaries/elements': [
        { type: 'routes', pattern: 'src/app/**' },                 // Expo Router routes (React Navigation: composition root)
        { type: 'bootstrap', pattern: 'src/bootstrap/**' },
        ...Object.keys(LAYERS).map((type) => ({ type, pattern: `src/features/*/${type}`, capture: ['feature'] })),
        { type: 'feature', pattern: 'src/features/*', capture: ['feature'] },   // after the layers: index.ts lands here
        { type: 'shared', pattern: 'src/shared/**' },
      ],
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/consistent-type-imports': 'error',
      // allow `onPress={() => onPress(id)}`; the default flags every void-returning arrow shorthand in JSX
      '@typescript-eslint/no-confusing-void-expression': ['error', { ignoreArrowShorthand: true }],
      'no-console': 'error',
      'no-restricted-syntax': ['error', {                     // inline style objects with literal values
        selector: 'JSXAttribute[name.name=/(^s|S)tyle$/] ObjectExpression > Property > :matches(Literal, UnaryExpression).value',
        message: 'No inline styles: use StyleSheet.create or a design-system primitive.',
      }],
      // routes -> bootstrap -> features -> shared; another feature only through its index.ts
      'boundaries/dependencies': ['error', { default: 'disallow', policies: [
        { from: { element: { types: ALL } }, allow: { to: { element: { type: 'feature', fileInternalPath: 'index.ts' } } } },
        { from: { element: { type: 'routes' } }, allow: { to: { element: { type: 'bootstrap' } } } },
        { from: { element: { type: 'feature' } }, allow: sameFeature(Object.keys(LAYERS)) },
        ...Object.entries(LAYERS).map(([type, to]) => ({ from: { element: { type } }, allow: sameFeature(to) })),
        { from: { element: { types: [...ALL, 'shared'] } }, allow: { to: { element: { type: 'shared' } } } },
      ] }],
    },
  },
  // test files: testing-library (RNTL follows the React rule set) and jest, plus the one test-only relaxation
  { files: ['**/*.test.{ts,tsx}'], ...testingLibrary.configs['flat/react'] },
  { files: ['**/*.test.{ts,tsx}'], ...jest.configs['flat/recommended'] },
  { files: ['**/*.test.{ts,tsx}'], rules: { '@typescript-eslint/no-non-null-assertion': 'off' } },
  // the one logger implementation that writes to the console (react-native-security §5)
  { files: ['src/shared/services/logger/ConsoleLogger.ts'], rules: { 'no-console': 'off' } },
  // eslint.config.mjs, jest.config.js, babel.config.js are outside tsconfig: lint them without type information
  { files: ['**/*.{js,mjs,cjs}'], ...tseslint.configs.disableTypeChecked },
  prettier,
);
```

`eslint-plugin-react-hooks` 7's `recommended` rules include the React Compiler checks. `boundaries/dependencies` turns the
dependency direction from `react-native-code-structure` §2 into a failing check: routes may import `bootstrap`, features'
`index.ts` and `shared`; another feature only through its `index.ts`; and inside one feature each layer imports only the
layers below it (the `captured: { feature }` template keeps a layer from reaching into another feature's layers). The
layer elements must come before `feature`, so only files at a feature's root (its `index.ts`) are type `feature`. A React
Navigation app without `src/bootstrap/` uses the same config: `src/app/` is its composition root and needs no other rights. It is the `eslint-plugin-boundaries` 7 syntax: `element-types` and `entry-point`, `rules:` and
string selectors are the deprecated v5 form and print migration warnings on every run. The selector rule flags
`style={{ color: 'red' }}` and `[styles.box, { padding: 8 }]` but not computed values (`{ width: wide ? 10 : 5 }`). Keep the `disableTypeChecked` override last (before `prettier`), otherwise
type-aware rules throw on config files ("not found by the project service").

Prove the boundaries once after setup: add `import { createServices } from '@bootstrap/createServices'` to a file under
`src/shared/`, `import { useOrders } from '@features/orders/hooks/useOrders'` to a file under `src/app/`, and
`import { useOrders } from '../hooks/useOrders'` to a file under `src/features/orders/components/`. `npm run lint` must
fail three times with `boundaries/dependencies`; then delete them. If it passes, the resolver is not resolving the
aliases. (Verified 2026-11-15 on ESLint 10.15, `typescript-eslint` 8.72, `eslint-plugin-boundaries` 7.4.3, resolver 4.4,
`eslint-plugin-react-hooks` 7.1, `eslint-plugin-testing-library` 7.16, `eslint-plugin-jest` 29.17, TypeScript 6.0,
Expo SDK 58 with Expo Router 58: seven such probes failed, cross-feature imports through `index.ts` passed.)

## 3. Prettier

```json
{ "singleQuote": true, "trailingComma": "all", "printWidth": 100, "semi": true }
```

Prettier owns formatting; ESLint carries no stylistic rules (`eslint-config-prettier` last). `.prettierignore` lists the
generated output, otherwise `prettier --check .` fails on the HTML report of the previous `jest --coverage` run and on
the bundle of `expo export` and the project of `expo prebuild`:

```
coverage
dist
ios
android
.expo
```

Code snippets in these skills are compressed for reading; run
`npx prettier --write .` after pasting them.

## 4. Pre-commit: fast feedback

```json
{ "lint-staged": {
  "*.{ts,tsx}": ["eslint --max-warnings 0 --fix", "prettier --write"],
  "*.{json,md,yml}": ["prettier --write"] } }
```

```sh
# .husky/pre-commit  (created by `npx husky init`; `prepare` installs it on npm install)
npx lint-staged && npm run typecheck
```

The hook is a convenience, not the gate: CI re-runs `npm run verify`, so `--no-verify` cannot get a violation merged.

## 5. Suppressions

A disable comment must name the rule and give a reason, and is reviewed like code:

```ts
// eslint-disable-next-line @typescript-eslint/no-unsafe-assignment -- third-party untyped callback, tracked in #123
```

Ban stale suppressions with `linterOptions.reportUnusedDisableDirectives: 'error'` (set in section 2) and `@ts-ignore` (use `@ts-expect-error` with a reason).

## Do / Don't

- ✅ Fix the code; change a rule only through a reviewed config PR.
- ✅ Keep `tsc` strict, including `noUncheckedIndexedAccess`.
- ✅ Run the exact verify script (`npm run verify`) in CI.
- ❌ `any`, `as unknown as T`, `// @ts-ignore` to pass the build.
- ❌ Warning-level rules that people learn to ignore.
- ❌ Linting only changed files in CI; lint the whole repo.
- ❌ Disabling `react-hooks/exhaustive-deps` instead of fixing the dependency.

## Cross-references

- `react-native-code-structure`: the boundaries and strict tsconfig being enforced.
- `react-native-ci`: runs `npm run verify` as a required check.
- `react-native-unit-tests`: test-specific lint rules and coverage gate.

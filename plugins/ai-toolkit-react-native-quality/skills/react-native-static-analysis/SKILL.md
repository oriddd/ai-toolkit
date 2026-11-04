---
name: react-native-static-analysis
description: Mechanically enforce style and catch bug classes in a React Native repo with TypeScript strict, ESLint flat config, Prettier, boundary rules, lint-staged and husky, all breaking the build in CI. Use when bootstrapping a repo, changing lint/tsc config, or when a violation appears. NOT for writing tests (use `react-native-unit-tests`) and NOT for pipeline wiring beyond the gate commands (use `react-native-ci`).
tier: must
applies_to: [mobile]
depends_on: [react-native-code-structure]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

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
tsconfig.json              # strict, see react-native-code-structure
.husky/pre-commit
package.json               # scripts + lint-staged
```

## Dependencies

```json
{ "devDependencies": { "typescript": "^5.6.0", "eslint": "^9.14.0", "typescript-eslint": "^8.13.0",
  "eslint-plugin-react-hooks": "^5.0.0", "eslint-plugin-react-native": "^5.0.0", "eslint-plugin-boundaries": "^5.0.0",
  "eslint-import-resolver-typescript": "^4.0.0",
  "eslint-plugin-testing-library": "^7.0.0", "eslint-plugin-jest": "^28.8.0", "eslint-config-prettier": "^9.1.0",
  "prettier": "^3.3.0", "husky": "^9.1.0", "lint-staged": "^15.2.0" } }
```

These ranges were installed together under ESLint 9 with no peer-dependency conflict (`eslint-plugin-react-native`
needs v5; v4 peers on ESLint <= 8). `typescript-eslint` supports TypeScript below 6.1, so keep `typescript` on 5.x.

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
import tseslint from 'typescript-eslint';
import reactHooks from 'eslint-plugin-react-hooks';
import reactNative from 'eslint-plugin-react-native';
import boundaries from 'eslint-plugin-boundaries';
import prettier from 'eslint-config-prettier';

export default tseslint.config(
  { ignores: ['node_modules', 'ios', 'android', 'coverage', '.expo'] },
  ...tseslint.configs.strictTypeChecked,
  { languageOptions: { parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname } } },
  {
    linterOptions: { reportUnusedDisableDirectives: 'error' },
    plugins: { 'react-hooks': reactHooks, 'react-native': reactNative, boundaries },
    settings: {
      // without this resolver the @app/* @shared/* aliases do not resolve and boundaries checks nothing
      'import/resolver': { typescript: { project: './tsconfig.json' } },
      'boundaries/elements': [
        { type: 'app', pattern: 'src/app/**' },
        { type: 'feature', pattern: 'src/features/*', capture: ['name'] },
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
      'react-native/no-inline-styles': 'error',
      'boundaries/element-types': ['error', { default: 'disallow', rules: [
        { from: 'app', allow: ['feature', 'shared'] },
        { from: 'feature', allow: ['feature', 'shared'] },
        { from: 'shared', allow: ['shared'] },
      ] }],
      // a feature is imported through its index.ts only (relative imports inside the feature are not affected)
      'boundaries/entry-point': ['error', { default: 'disallow', rules: [
        { target: 'feature', allow: 'index.ts' },
        { target: ['app', 'shared'], allow: '**' },
      ] }],
    },
  },
  { files: ['**/*.test.{ts,tsx}'], rules: { '@typescript-eslint/no-non-null-assertion': 'off' } },
  // eslint.config.mjs, jest.config.js, babel.config.js are outside tsconfig: lint them without type information
  { files: ['**/*.{js,mjs,cjs}'], ...tseslint.configs.disableTypeChecked },
  prettier,
);
```

Register `testing-library` and `jest` for `*.test.*` files the same way (their flat configs are
documented upstream). `boundaries/element-types` turns the dependency direction from
`react-native-code-structure` into a failing check and `boundaries/entry-point` limits cross-feature imports
to a feature's `index.ts`. Keep the `disableTypeChecked` override last (before `prettier`), otherwise
type-aware rules throw on config files ("not found by the project service").

Prove the boundaries once after setup: add `import { App } from '@app/App'` to a file under `src/shared/` and
`import { x } from '@features/orders/hooks/x'` to a file under `src/app/`. `npm run lint` must fail with
`boundaries/element-types` and `boundaries/entry-point`; then delete both. If it passes, the resolver
is not resolving the aliases. (Verified on ESLint 9.39, `eslint-plugin-boundaries` 5.4, resolver 4.4.)

## 3. Prettier

```json
{ "singleQuote": true, "trailingComma": "all", "printWidth": 100, "semi": true }
```

Prettier owns formatting; ESLint carries no stylistic rules (`eslint-config-prettier` last).

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

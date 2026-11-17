# From the Expo template to this layout

Deep dive for [`react-native-code-structure`](../SKILL.md) §1. Load it when you start an app with
`npx create-expo-app@latest <name> --template default@sdk-58` (the Expo SDK 58 default template) or adopt these skills in an app
generated from it. The template ships a demo app (tabs, themed components, an `@/*` alias) that this layout does not use.
`tools/render-rn-proof.sh` runs every step below on a fresh app and ends with `npm run verify` green.

## 1. Strip the template

```sh
rm -rf src/components src/constants src/hooks scripts src/global.css src/app/explore.tsx
rm -rf assets/images/tabIcons assets/images/expo-badge*.png assets/images/expo-logo.png \
       assets/images/logo-glow.png assets/images/react-logo*.png assets/images/tutorial-web.png
```

`assets/images/icon.png`, `splash-icon.png`, `favicon.png`, the `android-icon-*` files and `assets/expo.icon` stay: `app.json`
points at them. Then:

- Replace `src/app/_layout.tsx` and `src/app/index.tsx`: the template versions import the deleted `components/` and `hooks/`.
  Use the root layout of section 4 and `<Redirect href="/orders" />`.
- `package.json`: delete the `reset-project` script (its file is gone) and replace `"lint": "expo lint"` with the scripts of
  `react-native-static-analysis` §1. `npx expo lint` would otherwise generate a second, different ESLint config.
- `tsconfig.json`: remove the template's `"@/*"` and `"@/assets/*"` paths and add the three aliases of section 1. Two alias
  schemes in one app mean two ways to import the same file.
- Keep `app.json`; `app.config.ts` spreads it (`react-native-app-config-and-updates` §1), including its `plugins` and `experiments`.

## 2. `babel.config.js`

The Metro bundler and Jest do not read `tsconfig.json` `paths`; `babel-plugin-module-resolver` must repeat the aliases or the
app and every test fail with "Unable to resolve module @shared/...":

```js
// babel.config.js
module.exports = (api) => {
  api.cache(true);
  return {
    presets: ['babel-preset-expo'],
    plugins: [
      ['module-resolver', { alias: { '@bootstrap': './src/bootstrap', '@features': './src/features', '@shared': './src/shared' } }],
    ],
  };
};
```

Install it with `npm install -D babel-plugin-module-resolver`. `babel-preset-expo` already carries the React Native and (when
`experiments.reactCompiler` is on) React Compiler transforms. After changing `babel.config.js`, start Metro with
`npx expo start --clear`.

## 3. `jest.setup.ts`

`jest.config.js` is in `react-native-unit-tests`. Its setup file mocks each native module once, starts MSW and clears the
query clients a test created. `expo-secure-store` has no JavaScript implementation under Jest, so it gets a `Map`-backed
module (the adapter itself is tested against it):

```ts
// jest.setup.ts
import { server } from './src/test/msw/server';
import { clearTrackedClients } from './src/test/queryClients';

jest.mock('@react-native-community/netinfo', () =>
  jest.requireActual<object>('@react-native-community/netinfo/jest/netinfo-mock.js'));
jest.mock('@sentry/react-native', () => jest.requireActual<object>('./src/test/mocks/sentry'));
jest.mock('expo-secure-store', () => jest.requireActual<object>('./src/test/mocks/secureStore'));

beforeAll(() => { server.listen({ onUnhandledRequest: 'error' }); });
afterEach(() => { server.resetHandlers(); clearTrackedClients(); });
afterAll(() => { server.close(); });
```

The mock modules (`src/test/mocks/sentry.ts`, `secureStore.ts`) and the fakes are in
`react-native-unit-tests` (`references/test-harness.md`).
Bare apps with `react-native-keychain` mock that module the same way.

## 4. Check the result

```sh
npm run verify
```

`.prettierignore` and the ESLint `ignores` must list generated output (`coverage`, `dist`, `ios`, `android`, `.expo`), see
`react-native-static-analysis`: an `expo export` or `expo prebuild` run would otherwise put thousands of generated files
into `eslint` and `prettier`.

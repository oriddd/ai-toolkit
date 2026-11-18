---
name: react-native-unit-tests
description: >
  React Native unit tests with Jest + React Native Testing Library — behaviour-focused queries, MSW for network, fakes
  over mocks, positive/negative/edge cases, coverage threshold. Use when a component, hook, schema or service is
  created or coverage drops.
tier: must
applies_to: [mobile]
depends_on: [react-native-code-structure, react-native-state-and-data, react-native-error-handling]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-15
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# React Native Unit Tests Skill
## When to use

Use whenever a component, hook, schema, mapper or service is added or changed. Tests assert
**behaviour a user or caller can observe**, not implementation details.

## Layout

```
src/
├── features/orders/
│   ├── components/OrderCard.tsx
│   ├── components/OrderCard.test.tsx      # next to the unit
│   └── hooks/useOrders.test.tsx
└── test/
    ├── renderWithProviders.tsx            # fresh QueryClient + fake services
    ├── builders.ts                        # anOrderDto(), anOrder()
    ├── queryClients.ts                    # tracked(), clearTrackedClients()
    ├── fakes/FakeSecureStore.ts  FakeKeyValueStorage.ts  FakeAnalytics.ts
    ├── mocks/sentry.ts  secureStore.ts    # module mocks for jest.setup.ts
    ├── integration/sessionExpiry.test.tsx # section 3a
    └── msw/server.ts
jest.config.js  jest.setup.ts
```

## Dependencies

```json
{ "devDependencies": { "jest": "^30.0.0", "jest-expo": "~<expo-sdk>.0.0", "@testing-library/react-native": "^14.1.0",
  "test-renderer": "~<test-renderer-line>", "msw": "~2.6.0", "@types/jest": "^30.0.0" } }
```

- `jest-expo` is pinned to one Expo SDK: replace `<expo-sdk>` with the app's `expo` major (e.g. `~58.0.0` for SDK 58); use the latest stable SDK for a new app. Bare React Native apps drop `jest-expo` and use the `react-native` preset.
- `jest` 30 matches `jest-expo` 58, which is built on the Jest 30 packages; Jest 29 runs but installs two Jest stacks.
  `jest-expo` 58 takes the React Native preset from its peer `@react-native/jest-preset` (npm installs it; with
  `--legacy-peer-deps` add it yourself, at the app's React Native version, or the preset fails to load).
- RNTL 14 (React >= 19, React Native >= 0.78, Node `^22.13 || >=24`) renders with `test-renderer`, not the deprecated
  `react-test-renderer`: remove `react-test-renderer`, and pin the `test-renderer` line of your React minor
  (`<test-renderer-line>`: `1.3.0` for React 19.3, `1.2.0` for 19.2). **`render`, `renderHook`, `fireEvent` and `act` are
  async in v14: always `await` them** (`no-floating-promises` fails an un-awaited `render`). Stay on RNTL 13 (with
  `react-test-renderer` equal to `react`) only for a React 18 app.
- RNTL ships the jest matchers (`toBeOnTheScreen`, `toHaveTextContent`, ...) and registers them on import. Do not install
  `@testing-library/jest-native` (deprecated). RNTL unmounts after each test by itself: never call `cleanup()`.
- `msw` is held on `~2.6.0`: later 2.x releases pull ESM-only dependencies (`rettime`) and `msw` 3 is ESM-only; under
  `jest-expo` both fail with "Must use import to load ES Module", and `msw` 3 with `--experimental-vm-modules` returns
  responses without a status. Re-checked 2026-11-15 with `msw` 3.0.6, `jest` 30.5, `jest-expo` 58.0.14 on Node 26: same
  two failures (plain Jest 30 without `jest-expo` runs `msw` 3 under `--experimental-vm-modules`, so the blocker is the
  React Native environment's `fetch`). Move only when a version passes section 3's tests unchanged.

```js
// jest.config.js
module.exports = {
  preset: 'jest-expo', // or 'react-native' for bare apps
  setupFilesAfterEnv: ['<rootDir>/jest.setup.ts'],
  // msw maps the `react-native` export condition to null, so `msw/node` does not resolve without this
  testEnvironmentOptions: { customExportConditions: ['node', 'node-addons'] },
  coverageThreshold: { global: { branches: 80, functions: 80, lines: 85, statements: 85 } },
  collectCoverageFrom: ['src/**/*.{ts,tsx}', '!src/**/*.test.*', '!src/test/**', '!src/**/index.ts'],
};
```

The threshold is a build-breaking gate. The MSW setup above was run (2026-11-11) with `jest` 30.5, `jest-expo` 58,
`expo` 58, `react-native` 0.88, React 19.3, RNTL 14.1 with `test-renderer` 1.3, `msw` 2.6.9 on Node 26 (and on RNTL 13.3
with Jest 29): no `fetch`, `TextEncoder` or `BroadcastChannel` polyfill was needed there. On another
SDK or newer MSW, re-run the tests in section 3 first and treat any resolution or polyfill error as a setup problem to fix once in
`jest.config.js`/`jest.setup.ts`, not per test (unverified on other combinations).

## 1. Naming

`describe('<Unit>')` then `it('<does X> when <condition>')`:

```ts
it('shows an offline message when the request fails with a network error', ...)
```

## 2. Components: query like a user

```tsx
it('calls onPress with the order id when the card is pressed', async () => {
  const onPress = jest.fn();
  const user = userEvent.setup();
  await render(<OrderCard order={anOrder({ id: 'o-1', title: 'Shoes' })} onPress={onPress} />); // builder brands the id via orderSchema.parse

  await user.press(screen.getByRole('button', { name: /shoes/i }));

  expect(onPress).toHaveBeenCalledWith('o-1');
});
```

Prefer `getByRole`, `getByText`, `getByLabelText`; use `getByTestId` only when nothing accessible exists.
`OrderCard` is a `Pressable` with `accessibilityRole="button"`, which is what makes `getByRole('button')` match. Use `userEvent.setup()` over `fireEvent`. Use `findBy*` for async, never arbitrary `setTimeout`.

## 3. Hooks and network with MSW

```tsx
// test/msw/server.ts
export const server = setupServer();
// jest.setup.ts starts and stops `server` and mocks the native modules once (references/test-harness.md)

// useOrders.test.tsx
it('returns orders from the API', async () => {
  server.use(http.get('*/orders', () => HttpResponse.json([anOrderDto()])));
  const { result } = await renderHook(() => useOrders({}), { wrapper: testProviders() });
  await waitFor(() => expect(result.current.orders).toHaveLength(1));
});

it('exposes a retryable NetworkError when offline', async () => {
  server.use(http.get('*/orders', () => HttpResponse.error()));
  const { result } = await renderHook(() => useOrders({}), { wrapper: testProviders() });
  await waitFor(() => expect(result.current.error).toBeInstanceOf(NetworkError));
});
```

```tsx
// test/renderWithProviders.tsx
import type { PropsWithChildren } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { anonymousSession, createHttpClient } from '@shared/api-client/httpClient';
import { createConsentStore } from '@shared/consent/consent';
import { ServicesProvider, type Services } from '@shared/services/ServicesContext';
import { FakeAnalytics } from './fakes/FakeAnalytics';
import { FakeKeyValueStorage } from './fakes/FakeKeyValueStorage';
import { FakeSecureStore } from './fakes/FakeSecureStore';
import { tracked } from './queryClients';

const noop = () => undefined;

// every member of `Services` (react-native-code-structure §6): a missing one is a tsc error
export const fakeServices = (): Services => {
  const storage = new FakeKeyValueStorage();
  return {
    http: createHttpClient('https://api.test', anonymousSession),   // real client; MSW answers
    storage,
    secure: new FakeSecureStore(),                                   // Map-backed fakes
    consent: createConsentStore(storage),                            // the real store over the fake storage
    logger: { debug: noop, info: noop, warn: noop, error: noop },
    errorReporter: { report: noop },
    analytics: new FakeAnalytics(),
  };
};

export const testProviders = (services: Services = fakeServices()) => {
  const client = tracked(new QueryClient({ defaultOptions: { queries: { retry: false } } }));
  return ({ children }: PropsWithChildren) => (
    <ServicesProvider value={services}>
      <QueryClientProvider client={client}>{children}</QueryClientProvider>
    </ServicesProvider>
  );
};
```

Each call builds a new `QueryClient`, so tests share no cache. Every client a test creates goes through `tracked`
(`test/queryClients.ts`, [references/test-harness.md](./references/test-harness.md)): it sets `gcTime: Infinity` on queries **and**
mutations and clears the client after each test. Without it a 5-minute garbage-collection timer per query or mutation keeps
the worker alive: `npx jest src/bootstrap` never returns and the full run prints "A worker process has failed to exit
gracefully". Use `tracked(createQueryClient(...))` for the app's own client factory too (`react-native-state-and-data` §7),
and never render the real `QueryProvider` in a test (it owns a client you cannot clear): test its policy through
`createQueryClient` and `createAppQueryClient`.

## 3a. A 401 ends the session

The session-expiry chain of `react-native-security` §1b and `react-native-state-and-data` §7 is proved end to end with the
real api-client, the real `createAuthSession`, a fake `SecureStore`, MSW and `renderRouter` over the real `RootNavigator`:
a 401 survives one failed refresh, the tokens and the cache are cleared, and the router lands on `/sign-in`; the twin has the
refresh succeed and the user stays. Code: [references/session-expiry-test.md](./references/session-expiry-test.md). It lives in
`src/test/integration/` because it crosses the `routes`, `bootstrap` and feature layers that `eslint-plugin-boundaries` keeps apart.

## 3b. Screens behind Expo Router routes

Test a screen on its own with `render` and the test providers. To prove navigation (a press opens the right route,
a deep-link path renders the right screen), render an in-memory route tree with `renderRouter` from
`expo-router/testing-library` (async, peers on RNTL >= 14):

```tsx
import { userEvent } from '@testing-library/react-native';          // expo-router/testing-library exports it as a type only
import { renderRouter, screen } from 'expo-router/testing-library';

it('opens the order detail when an order card is pressed', async () => {
  server.use(http.get('*/orders', () => HttpResponse.json([anOrderDto({ id: 'o-1', title: 'Shoes' })])),
    http.get('*/orders/o-1', () => HttpResponse.json(anOrderDto({ id: 'o-1', title: 'Shoes' }))));
  const Providers = testProviders();
  const user = userEvent.setup();
  await renderRouter(
    { _layout: () => <Providers><Slot /></Providers>, 'orders/index': OrdersListScreen, 'orders/[id]': OrderDetailScreen },
    { initialUrl: '/orders' },
  );

  await user.press(await screen.findByRole('button', { name: /shoes/i }));

  expect(screen).toHavePathname('/orders/o-1');
});
```

The route map points at the feature screens, not at `src/app/` files, so the real root layout (Sentry, real services)
never runs. `renderRouter` switches the test file to Jest fake timers: keep tests that need real time (the api-client
timeout) in another file, or call `jest.useRealTimers()` first.

## 4. Fakes over mocks

Inject in-memory fakes for the interfaces (`SecureStore`, `Analytics`, `Logger`) via the services
provider. A fake has real behaviour (a `Map`), so tests assert outcomes (`await store.get('token')`), not
that a method was called. Reserve `jest.fn()` for callback props. Mock native modules only in `jest.setup.ts`
(`react-native-code-structure`, `references/expo-template-setup.md` §3; the fakes and mock modules are in
[references/test-harness.md](./references/test-harness.md)): NetInfo with the mock it ships, `expo-secure-store` /
`react-native-keychain` with a small `Map`-backed module in `src/test/mocks/`, and `@sentry/react-native` with `jest.fn()` stubs for `init`, `captureException`,
`addBreadcrumb`, `setUser` and an identity `wrap` (importing the real SDK starts a timer that keeps Jest alive).
A test of the real adapter (`createExpoSecureStore`, `SentryErrorReporter`) runs against that module mock.

## 5. Positive, negative, edge

| Unit | Positive | Negative | Edge |
| --- | --- | --- | --- |
| `signupSchema` | valid form passes | missing `@` rejected | 12-char password boundary, trimmed whitespace |
| `mapHttpError` | 404 -> `NotFoundError`; known problem `code` wins over status | 418 -> `UNKNOWN` | 500 and 503 are retryable; non-JSON body |
| api-client / `createAuthSession` | 401 -> one refresh, retried with the new token | rejected refresh -> `UnauthorizedError` | two concurrent 401s share one refresh; timeout -> `NetworkError` |
| `SignupScreen` / `SignInScreen` | valid form submits; sign-in stores tokens and signs the session in | invalid form sends nothing; a 422 field error appears in the form | unmapped server code shows `vm.serverRejected` |
| `OrdersListScreen` | renders items | shows `ErrorState` on failure | empty list shows empty state |
| `createQueryClient` | retries a 5xx twice, reports it once; a 401 calls `onUnauthorized(client)` | 404 not retried, not reported | offline not reported; 401 from a mutation too |
| Session expiry (3a) | refresh succeeds: stays signed in | refresh rejected: signed out, cache cleared, redirected | the retry carries the rotated token |
| Consent and deletion | granted consent forwards events | withdrawn consent drops them; failed deletion keeps the session | corrupt stored consent falls back to none |
| `scrubEvent` / `scrubBreadcrumb` | keeps `user.id`, url path | drops email, token, query string | user without id |
| `parseEnv` | valid build config | `http://` api url throws | missing value throws |
| Navigation | `renderRouter`: pressing a card opens `/orders/[id]` | invalid route param shows not-found | (React Navigation: `AppProviders` + root navigator render the first screen) |

Table-driven `it.each` is encouraged for mappers and schemas. Test the catalogue: every `ErrorCode` has a message.

## 6. Coverage and speed

Run `jest --ci --coverage` in CI (see `react-native-ci`). Coverage is a floor, not the goal: a test
without an assertion about behaviour does not count. Keep unit tests under a few ms each, with no real
network, timers or device APIs; use `jest.useFakeTimers()` explicitly where time matters.

## Do / Don't

- ✅ Build test data with named builders in `src/test/builders.ts`: `anOrderDto(overrides)` returns the wire
  shape (for MSW), `anOrder(overrides)` returns `orderSchema.parse(anOrderDto(overrides))`, a branded `Order`.
- ✅ One behaviour per test; arrange / act / assert visible.
- ✅ Assert on what the user sees or what the hook returns.
- ❌ Snapshot tests of whole screens as the main assertion.
- ❌ Testing state variables, hook internals or `useEffect` call counts.
- ❌ `jest.mock` of your own modules to dodge injecting a fake.
- ❌ Skipped tests (`it.skip`) merged to main.

## Cross-references

- `react-native-state-and-data`: query hooks tested here with MSW.
- `react-native-error-handling`: mapper and catalogue tests.
- `react-native-input-validation`: schema test cases.
- `react-native-e2e-tests`: what to leave to Maestro.
- `react-native-static-analysis`: lint rules for tests (`eslint-plugin-testing-library`).

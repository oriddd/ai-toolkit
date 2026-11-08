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
last_reviewed: 2026-11-03
---

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
    ├── fakes/FakeSecureStore.ts  FakeAnalytics.ts
    └── msw/server.ts  handlers.ts
jest.config.js  jest.setup.ts
```

## Dependencies

```json
{ "devDependencies": { "jest": "^29.7.0", "jest-expo": "~<expo-sdk>.0.0", "@testing-library/react-native": "^13.3.0",
  "msw": "~2.6.0", "@types/jest": "^29.5.0" } }
```

- `jest-expo` is pinned to one Expo SDK: replace `<expo-sdk>` with the app's `expo` major (e.g. `~52.0.0` for SDK 52); use the latest stable SDK for a new app. Bare React Native apps drop `jest-expo` and use the `react-native` preset.
- RNTL 12.4+ ships the jest matchers (`toBeOnTheScreen`, `toHaveTextContent`, ...) and registers them when you import from
  `@testing-library/react-native`. Do not install `@testing-library/jest-native` (deprecated); v12 is no longer maintained, so use v13.
- `msw` is held on `~2.6.0`: newer 2.x releases pull ESM-only dependencies that Jest fails to parse
  ("Cannot use import statement outside a module" in `rettime`) unless you extend `transformIgnorePatterns`.

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

The threshold is a build-breaking gate. The MSW setup above was run with `jest-expo` 52, `expo` 52, `react-native` 0.76,
RNTL 13, `msw` 2.6.9 on Node 22: no `fetch`, `TextEncoder` or `BroadcastChannel` polyfill was needed there. On another
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
  render(<OrderCard order={anOrder({ id: 'o-1', title: 'Shoes' })} onPress={onPress} />); // builder brands the id via orderSchema.parse

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
// jest.setup.ts
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => { server.resetHandlers(); cleanup(); });
afterAll(() => server.close());

// useOrders.test.tsx
it('returns orders from the API', async () => {
  server.use(http.get('*/orders', () => HttpResponse.json([anOrderDto()])));
  const { result } = renderHook(() => useOrders({}), { wrapper: testProviders() });
  await waitFor(() => expect(result.current.orders).toHaveLength(1));
});

it('exposes a retryable NetworkError when offline', async () => {
  server.use(http.get('*/orders', () => HttpResponse.error()));
  const { result } = renderHook(() => useOrders({}), { wrapper: testProviders() });
  await waitFor(() => expect(result.current.error).toBeInstanceOf(NetworkError));
});
```

`testProviders()` builds a new `QueryClient({ defaultOptions: { queries: { retry: false, gcTime: Infinity } } })` per test and
returns a wrapper component around it; `gcTime: Infinity` stops cache timers from keeping Jest from exiting.

## 4. Fakes over mocks

Inject in-memory fakes for the interfaces (`SecureStore`, `Analytics`, `Logger`) via the services
provider. A fake has real behaviour (a `Map`), so tests assert outcomes (`await store.get('token')`), not
that a method was called. Reserve `jest.fn()` for callback props. Mock native modules only in `jest.setup.ts`.

## 5. Positive, negative, edge

| Unit | Positive | Negative | Edge |
| --- | --- | --- | --- |
| `signupSchema` | valid form passes | missing `@` rejected | 12-char password boundary, trimmed whitespace |
| `mapHttpError` | 404 -> `NotFoundError` | 418 -> `UNKNOWN` | 500 and 503 are retryable |
| `OrdersListScreen` | renders items | shows `ErrorState` on failure | empty list shows empty state |

Table-driven `it.each` is encouraged for mappers and schemas. Test the catalogue: every `ErrorCode` has a message.

## 6. Coverage and speed

Run `jest --ci --coverage` in CI (see `react-native-ci`). Coverage is a floor, not the goal: a test
without an assertion about behaviour does not count. Keep unit tests under a few ms each, with no real
network, timers or device APIs; use `jest.useFakeTimers()` explicitly where time matters.

## Do / Don't

- ✅ Build test data with named builders (`anOrder({...})`).
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

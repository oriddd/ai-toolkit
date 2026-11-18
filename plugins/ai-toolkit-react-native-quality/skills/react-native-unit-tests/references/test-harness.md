# Test harness: fakes, module mocks, MSW server, query-client tracking

Deep dive for [`react-native-unit-tests`](../SKILL.md) sections 3 and 4. Every file below is rendered into a fresh Expo SDK 58
app by `tools/render-rn-proof.sh` and passes `npm run verify` there. `jest.setup.ts` (which wires them) is in
`react-native-code-structure`, `references/expo-template-setup.md` §3.

## 1. Fakes

A fake has real behaviour (a `Map`, an array), so a test asserts outcomes instead of calls. They implement the same interfaces
the app injects through the services provider.

```ts
// src/test/fakes/FakeSecureStore.ts
import type { SecureStore } from '@shared/services/secure-storage/SecureStore';
export class FakeSecureStore implements SecureStore {
  private readonly m = new Map<string, string>();
  get(key: string) {
    return Promise.resolve(this.m.get(key) ?? null);
  }
  set(key: string, value: string) {
    this.m.set(key, value);
    return Promise.resolve();
  }
  remove(key: string) {
    this.m.delete(key);
    return Promise.resolve();
  }
}
```

```ts
// src/test/fakes/FakeKeyValueStorage.ts
import type { KeyValueStorage } from '@shared/services/storage/KeyValueStorage';

export class FakeKeyValueStorage implements KeyValueStorage {
  private readonly entries = new Map<string, string>();

  get(key: string) {
    return Promise.resolve(this.entries.get(key) ?? null);
  }

  set(key: string, value: string) {
    this.entries.set(key, value);
    return Promise.resolve();
  }
}
```

```ts
// src/test/fakes/FakeAnalytics.ts
import type { Analytics, AnalyticsEvent } from '@shared/services/analytics/events';

export class FakeAnalytics implements Analytics {
  readonly events: AnalyticsEvent[] = [];
  userId: string | null = null;

  track(event: AnalyticsEvent) {
    this.events.push(event);
  }

  setUserId(id: string | null) {
    this.userId = id;
  }
}
```

## 2. Module mocks (`jest.setup.ts` points at them)

Native modules have no implementation under Jest. `expo-secure-store` gets a `Map`-backed module; `@sentry/react-native` gets
`jest.fn()` stubs (importing the real SDK starts a timer that keeps Jest alive). NetInfo ships its own mock.

```ts
// src/test/mocks/secureStore.ts
const items = new Map<string, string>();

export const WHEN_UNLOCKED_THIS_DEVICE_ONLY = 'WHEN_UNLOCKED_THIS_DEVICE_ONLY';
export const getItemAsync = (key: string) => Promise.resolve(items.get(key) ?? null);
export const setItemAsync = (key: string, value: string) => {
  items.set(key, value);
  return Promise.resolve();
};
export const deleteItemAsync = (key: string) => {
  items.delete(key);
  return Promise.resolve();
};
```

```ts
// src/test/mocks/sentry.ts
export const init = jest.fn();
export const captureException = jest.fn();
export const addBreadcrumb = jest.fn();
export const setUser = jest.fn();
export const reactNavigationIntegration = jest.fn(() => ({ registerNavigationContainer: jest.fn() }));
export const wrap = <T>(component: T): T => component;
```

A bare app with `react-native-keychain` adds `src/test/mocks/keychain.ts` (`Map`-backed `getGenericPassword`,
`setGenericPassword`, `resetGenericPassword`, `ACCESSIBLE`) and mocks that module the same way.

## 3. MSW server and query-client tracking

```ts
// src/test/msw/server.ts
import { setupServer } from 'msw/node';
export const server = setupServer();
```

```ts
// src/test/queryClients.ts
import type { QueryClient } from '@tanstack/react-query';
const created: QueryClient[] = [];
export const tracked = (client: QueryClient): QueryClient => {
  const { queries, mutations } = client.getDefaultOptions();
  client.setDefaultOptions({
    queries: { ...queries, gcTime: Infinity },
    mutations: { ...mutations, gcTime: Infinity },
  });
  created.push(client);
  return client;
};
export const clearTrackedClients = () => {
  for (const client of created.splice(0)) client.clear();
};
```

`tracked` is why `npx jest <file>` exits by itself: without `gcTime: Infinity` every query and mutation leaves a 5-minute timer.
`afterEach` in `jest.setup.ts` calls `clearTrackedClients`.

## 4. Builders

```ts
// src/test/builders.ts
import { orderSchema } from '@features/orders/model/order';

export const ORDER_ID = '3f2b1c0e-6a5d-4e8f-9b7a-1c2d3e4f5a6b';

export const anOrderDto = (overrides: Partial<{ id: string; title: string; status: string }> = {}) => ({
  id: ORDER_ID,
  title: 'Shoes',
  status: 'open',
  ...overrides,
});

export const anOrder = (overrides: Partial<{ id: string; title: string; status: string }> = {}) =>
  orderSchema.parse(anOrderDto(overrides));
```

`anOrderDto` returns the wire shape (for MSW handlers), `anOrder` returns a branded `Order` through `orderSchema.parse`.

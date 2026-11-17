---
name: react-native-state-and-data
description: >
  React Native data layer — server state in TanStack Query behind one api client, client state in Zustand, query-key
  conventions, optimistic updates, offline/retry stance. Use when a screen needs remote data, a mutation, a cache, or
  shared UI/session state.
tier: must
applies_to: [mobile]
depends_on: [react-native-code-structure]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-15
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# React Native State and Data Skill
## When to use

Use whenever a component needs data that lives on a server, a write to a server, or state shared
between screens. Components never fetch; they render what a hook returns.

Two kinds of state, two tools, never mixed:

| State | Owner | Examples |
| --- | --- | --- |
| Server state (cacheable, can go stale) | TanStack Query | orders, profile, feed |
| Client state (ours alone) | Zustand (or `useState` if local) | session flag, selected tab, draft filters |

## Layout

```
shared/api-client/   httpClient.ts  types.ts   # mapHttpError lives in shared/errors
features/orders/
├── api/       ordersApi.ts        # only place that calls the http client
├── hooks/     useOrders.ts  useCancelOrder.ts  orderKeys.ts  useOrdersApi.ts
└── model/     order.ts  orderSchemas.ts
shared/state/ useSessionStore.ts
```

## Dependencies

```json
{ "dependencies": { "@tanstack/react-query": "^5.59.0", "zustand": "^5.0.0",
  "@react-native-community/netinfo": "<sdk-matched>" } }
```

Packages with native code (`netinfo`) must match the Expo SDK: add them with `npx expo install <package>` (SDK 58:
`netinfo` 12.0.1), never a hand-written range; bare apps take the version the library documents. TanStack Query 5.107 deprecates `fetchQuery`, `prefetchQuery` and
`ensureQueryData` in favour of `queryClient.query(options)`; `no-deprecated` (`react-native-static-analysis`) fails the old names.

## 1. One api-client, one mapping point

```ts
// shared/api-client/httpClient.ts
import type { z } from 'zod';                             // type position only: `consistent-type-imports` rejects a value import
export type HttpRequest = Omit<RequestInit, 'headers' | 'body'> & {
  path: string;
  query?: Record<string, string | number | boolean | undefined>;
  body?: unknown;                                        // JSON-serialised by the client (POST/PUT/PATCH payloads)
  timeoutMs?: number;                                    // default 15 s
};
export interface HttpClient { request<T>(req: HttpRequest, schema: z.ZodType<T>): Promise<T>; }  // input type defaults to unknown: a branded or transformed schema's input differs from its output

export interface AuthSession {                           // implemented in shared/session (react-native-security §1)
  getToken(): Promise<string | null>;
  refresh(): Promise<string | null>;                     // new access token, or null: the session is over
}
export const anonymousSession: AuthSession = { getToken: () => Promise.resolve(null), refresh: () => Promise.resolve(null) };

const DEFAULT_TIMEOUT_MS = 15_000;

export const toQueryString = (query: HttpRequest['query']): string => {
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(query ?? {})) if (v !== undefined) params.append(k, String(v));
  const s = params.toString();
  return s ? `?${s}` : '';
};

// one signal for the caller's cancellation (TanStack's `signal`) and our timeout; React Native 0.85 and earlier
// lack AbortSignal.timeout / .any (0.88 has both)
const withTimeout = (outer: AbortSignal | null | undefined, ms: number) => {
  const controller = new AbortController();
  const abort = () => { controller.abort(); };
  const timer = setTimeout(abort, ms);
  if (outer?.aborted) abort();
  else outer?.addEventListener('abort', abort);
  return { signal: controller.signal, clear: () => { clearTimeout(timer); outer?.removeEventListener('abort', abort); } };
};

export const createHttpClient = (baseUrl: string, session: AuthSession): HttpClient => ({
  async request(req, schema) {
    const { path, query, body, signal, timeoutMs = DEFAULT_TIMEOUT_MS, ...init } = req;  // ours, not RequestInit fields
    const send = async (token: string | null): Promise<Response> => {
      const timeout = withTimeout(signal, timeoutMs);
      try {
        return await fetch(`${baseUrl}${path}${toQueryString(query)}`, {
          ...init,
          signal: timeout.signal,
          headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), 'Content-Type': 'application/json', Accept: 'application/json' },
          ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        });
      } catch (cause: unknown) {
        throw toNetworkError(cause);                     // offline, timeout and cancellation: retryable NetworkError
      } finally {
        timeout.clear();
      }
    };
    let res = await send(await session.getToken());
    if (res.status === 401) {                            // one refresh (single-flight in the session), one retry
      const fresh = await session.refresh();
      if (fresh) res = await send(fresh);
    }
    if (!res.ok) throw await mapHttpError(res);          // see react-native-error-handling (reads the problem body)
    const payload: unknown = res.status === 204                 // 204 has no body: res.json() would throw
      ? undefined
      : await res.json().catch((cause: unknown) => { throw toContractError(cause); });  // malformed 2xx body
    const parsed = schema.safeParse(payload);            // validate the contract at the edge
    if (!parsed.success) throw toContractError(parsed.error);  // a ZodError never escapes: it becomes an AppError here
    return parsed.data;
  },
});
```

The token goes into the headers only here. An endpoint that answers 204 is called with `z.undefined()` as its schema.
Every failure the client throws is an `AppError` (network, timeout, HTTP status,
contract), which is what makes the `AppError` narrowing in the hooks below true. A 401 still left after the one refresh
reaches the caller as `UnauthorizedError`, and the `QueryCache` handler signs out (`react-native-security` §1).
Pass TanStack's `signal` through (sections 2 and 4) so a query that unmounts or is cancelled aborts its request.

The client is provided through the services context in `shared/services/` (`useServices`, see `react-native-code-structure`) so tests inject a fake.

## 2. Feature api module

```ts
// features/orders/model/order.ts: a type alias (not an interface) so it fits HttpRequest['query']
export type OrderFilter = { status?: Order['status']; customerId?: string };

// features/orders/api/ordersApi.ts
export const createOrdersApi = (http: HttpClient) => ({
  list: (filter: OrderFilter, signal?: AbortSignal): Promise<Order[]> =>
    http.request({ path: '/orders', method: 'GET', query: filter, signal: signal ?? null }, z.array(orderSchema)),
  get: (id: OrderId, signal?: AbortSignal): Promise<Order> =>
    http.request({ path: `/orders/${encodeURIComponent(id)}`, method: 'GET', signal: signal ?? null }, orderSchema),
  cancel: (id: OrderId): Promise<Order> =>
    http.request({ path: `/orders/${encodeURIComponent(id)}/cancel`, method: 'POST' }, orderSchema),
});
```

Plain functions, typed in and out, no React and no caching. Reads take an optional `signal` (`signal ?? null`:
`exactOptionalPropertyTypes` forbids `undefined` for `RequestInit.signal`). Path values are `encodeURIComponent`-encoded;
query values go through `query`, which `URLSearchParams` encodes.

## 3. Query keys: a factory per feature

```ts
// features/orders/hooks/orderKeys.ts
export const orderKeys = {
  all: ['orders'] as const,
  lists: () => [...orderKeys.all, 'list'] as const,
  list: (filter: OrderFilter) => [...orderKeys.lists(), filter] as const,
  detail: (id: OrderId) => [...orderKeys.all, 'detail', id] as const,
};
```

Never inline key arrays. Invalidate by prefix: `invalidateQueries({ queryKey: orderKeys.all })`.
`orderKeys.all` matches list **and** detail caches, which hold different shapes (`Order[]` vs `Order`), so cache
reads and writes that assume one shape must target `lists()` or `detail(id)`, never `all`.

## 4. Query hooks return what the screen needs

```ts
// features/orders/hooks/useOrdersApi.ts: the feature builds its api from the shared http client
export const useOrdersApi = () => {
  const { http } = useServices();                        // @shared/services/ServicesContext
  return useMemo(() => createOrdersApi(http), [http]);
};

const NO_ORDERS: Order[] = [];                           // one stable empty array: `?? []` would be new each render

export function useOrders(filter: OrderFilter) {
  const ordersApi = useOrdersApi();
  const q = useQuery({ queryKey: orderKeys.list(filter), queryFn: ({ signal }) => ordersApi.list(filter, signal), staleTime: 30_000 });
  return {
    orders: q.data ?? NO_ORDERS,
    isLoading: q.isPending,
    isOffline: q.fetchStatus === 'paused',                 // offline with nothing cached: show it, do not spin
    error: q.error,                                        // AppError | null, via the Register below
    refetch: q.refetch,
  };
}
```

```ts
export function useOrder(id: OrderId) {                  // detail: same shape, keyed by orderKeys.detail
  const ordersApi = useOrdersApi();
  const q = useQuery({ queryKey: orderKeys.detail(id), queryFn: ({ signal }) => ordersApi.get(id, signal) });
  return { order: q.data, error: q.error, refetch: q.refetch };
}
```

The error type is `AppError` because the api-client throws nothing else (section 1) and TanStack Query is
told so once, instead of an `as` cast in every hook:

```ts
// shared/api-client/queryTypes.ts
import type { AppError } from '@shared/errors/AppError';
declare module '@tanstack/react-query' {
  interface Register { defaultError: AppError }
}
```

The screen never sees raw `Response` or `AxiosError`.

## 5. Mutations and optimistic updates

```ts
export function useCancelOrder() {
  const qc = useQueryClient();
  const ordersApi = useOrdersApi();
  return useMutation({
    mutationFn: ordersApi.cancel,
    onMutate: async (id) => {
      await qc.cancelQueries({ queryKey: orderKeys.all });
      const previousLists = qc.getQueriesData<Order[]>({ queryKey: orderKeys.lists() });
      const previousDetail = qc.getQueryData<Order>(orderKeys.detail(id));
      const cancelled = (o: Order): Order => ({ ...o, status: 'cancelled' });
      qc.setQueriesData<Order[]>({ queryKey: orderKeys.lists() }, (old) => old?.map((o) => (o.id === id ? cancelled(o) : o)));
      qc.setQueryData<Order>(orderKeys.detail(id), (old) => (old ? cancelled(old) : old));
      return { previousLists, previousDetail };
    },
    onError: (_e, id, ctx) => {
      ctx?.previousLists.forEach(([key, data]) => qc.setQueryData(key, data));
      qc.setQueryData(orderKeys.detail(id), ctx?.previousDetail); // undefined is a no-op: nothing was cached
    },
    onSettled: () => qc.invalidateQueries({ queryKey: orderKeys.all }),
  });
}
```

Optimistic only when failure is rare and rollback is clear; otherwise show a pending state.

## 6. Client state with Zustand

```ts
// shared/state/useSessionStore.ts
type UserId = string;     // or a branded id from a shared schema; `shared` cannot import feature types
type SessionState = { userId: UserId | null; signIn: (id: UserId) => void; signOut: () => void };
export const useSessionStore = create<SessionState>()((set) => ({
  userId: null, signIn: (userId) => set({ userId }), signOut: () => set({ userId: null }),
}));
// consumers select a slice: const userId = useSessionStore((s) => s.userId);
```

One small store per concern. Never copy server data into a store; the query cache is its owner.

## 7. Offline and retry stance

```tsx
// bootstrap/QueryProvider.tsx (React Navigation apps: app/providers/)
onlineManager.setEventListener((set) => NetInfo.addEventListener((s) => { set(!!s.isConnected); }));
focusManager.setEventListener((handleFocus) => {          // React Native has no window focus: use AppState
  const sub = AppState.addEventListener('change', (state) => { handleFocus(state === 'active'); });
  return () => { sub.remove(); };
});

type QueryClientDeps = {
  errorReporter: ErrorReporter;
  onUnauthorized: (client: QueryClient) => void;          // the client it was built into: sign-out clears its cache
};

// exported so the retry, reporting and sign-out policy is unit-tested without rendering the provider
export const createQueryClient = ({ errorReporter, onUnauthorized }: QueryClientDeps) => {
  const handleError = (e: unknown) => {
    if (e instanceof UnauthorizedError) onUnauthorized(client);   // refresh already failed (section 1): the session is over
    else if (isReportable(e)) errorReporter.report(e);
  };
  const client = new QueryClient({
    queryCache: new QueryCache({ onError: handleError }),
    mutationCache: new MutationCache({ onError: handleError }),
    defaultOptions: {
      queries: { retry: (n, e) => n < 2 && e.retryable, networkMode: 'offlineFirst' },
      mutations: { retry: 0 },
    },
  });
  return client;
};

export const createAppQueryClient = ({ errorReporter, secure }: Services) =>
  createQueryClient({
    errorReporter,
    onUnauthorized: (client) => {
      signOut(client, secure).catch((e: unknown) => { errorReporter.report(e); });   // react-native-security §1
    },
  });

export const QueryProvider = ({ children }: PropsWithChildren) => {
  const services = useServices();                           // the client lives inside the services provider
  const [client] = useState(() => createAppQueryClient(services));
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
};
```

`Services` carries `secure: SecureStore` (built in `createServices`, `react-native-security` §1b). The chain for an expired
session: a 401 makes `session.refresh()` run once for all concurrent requests and return `null`, `UnauthorizedError` reaches
the cache's `onError`, `signOut` clears the tokens, both caches and the session store, and the root navigator redirects
because it reads that store (`RootNavigator`, `react-native-security` §1b; React Navigation apps render
`{signedIn ? <AppStack /> : <AuthStack />}`). `UnauthorizedError` is never reported: it is an expected outcome. Both the
401-then-signed-out flow and the refresh-succeeds flow are tested in `react-native-unit-tests` §3a.

`isReportable` is the "report unexpected errors only" rule from `react-native-error-handling` §6. Render
`QueryProvider` inside `ServicesProvider`. With `offlineFirst`, a query with no cached data pauses while
offline (`fetchStatus === 'paused'`) and resumes when `onlineManager` reports a connection: the hook exposes
that as `isOffline` so the screen shows an offline state instead of a spinner.

- Retry reads only for retryable `AppError`s (network, 5xx). Never retry 4xx.
- Mutations are not retried automatically unless idempotent (send an idempotency key).
- Persist the cache (`@tanstack/react-query-persist-client`) only when the product needs offline reads.

## Do / Don't

- ✅ Validate responses with zod at the api-client edge.
- ✅ Every request has a timeout; queries pass TanStack's `signal` down to `fetch`.
- ✅ One query-key factory per feature; invalidate by prefix.
- ✅ Select narrow Zustand slices to avoid re-renders.
- ❌ `useEffect(() => { fetch(...) }, [])` in a component.
- ❌ Server data mirrored into Zustand or Redux.
- ❌ Several HTTP clients or per-call error handling; map errors once. (The session's unauthenticated client for the
  refresh call is the one exception: same factory, `anonymousSession`.)
- ❌ A global store for state one screen owns; use `useState`.

## Cross-references

- `react-native-code-structure`: where api, hooks and model files live.
- `react-native-error-handling`: `AppError` and `mapHttpError`, used by the client.
- `react-native-input-validation`: shared zod schemas for request and response types.
- `react-native-unit-tests`: testing hooks with MSW and a fresh `QueryClient`; the 401 to sign-out test.
- `react-native-security`: `signOut`, `createAuthSession` and the single-flight refresh.

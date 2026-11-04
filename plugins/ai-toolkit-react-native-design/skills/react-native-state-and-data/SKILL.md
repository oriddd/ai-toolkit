---
name: react-native-state-and-data
description: Apply the canonical data layer for React Native, with server state in TanStack Query behind a single api-client layer, client state in Zustand, query-key conventions, optimistic updates and an offline/retry stance. Use when a screen needs remote data, a mutation, a cache, or shared UI/session state. NOT for folder layout (use `react-native-code-structure`), NOT for mapping failures to user messages (use `react-native-error-handling`).
tier: must
applies_to: [mobile]
depends_on: [react-native-code-structure, react-native-error-handling]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

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
├── hooks/     useOrders.ts  useCancelOrder.ts  orderKeys.ts
└── model/     order.ts  orderSchemas.ts
shared/state/ useSessionStore.ts
```

## Dependencies

```json
{ "dependencies": { "@tanstack/react-query": "^5.59.0", "zustand": "^5.0.0",
  "@react-native-community/netinfo": "^11.4.0" } }
```

## 1. One api-client, one mapping point

```ts
// shared/api-client/httpClient.ts
export type HttpRequest = Omit<RequestInit, 'headers' | 'body'> & { path: string; query?: Record<string, string | number | boolean | undefined> };
export interface HttpClient { request<T>(req: HttpRequest, schema: z.ZodType<T, z.ZodTypeDef, unknown>): Promise<T>; }  // input type unknown: a branded or transformed schema's input differs from its output

export const toQueryString = (query: HttpRequest['query']): string => {
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(query ?? {})) if (v !== undefined) params.append(k, String(v));
  const s = params.toString();
  return s ? `?${s}` : '';
};

export const createHttpClient = (baseUrl: string, getToken: () => Promise<string | null>): HttpClient => ({
  async request(req, schema) {
    const { path, query, ...init } = req;               // path/query are ours, not RequestInit fields
    const res = await fetch(`${baseUrl}${path}${toQueryString(query)}`, { ...init, headers: await authHeaders(getToken) })
      .catch((cause: unknown) => { throw toNetworkError(cause); });
    if (!res.ok) throw mapHttpError(res);                // see react-native-error-handling
    return schema.parse(await res.json());               // validate the contract at the edge
  },
});
```

The client is provided through the services context in `shared/services/` (`useServices`, see `react-native-code-structure`) so tests inject a fake.

## 2. Feature api module

```ts
// features/orders/api/ordersApi.ts
export const createOrdersApi = (http: HttpClient) => ({
  list: (filter: OrderFilter): Promise<Order[]> =>
    http.request({ path: '/orders', method: 'GET', query: filter }, z.array(orderSchema)),
  cancel: (id: OrderId): Promise<Order> => http.request({ path: `/orders/${id}/cancel`, method: 'POST' }, orderSchema),
});
```

Plain functions, typed in and out, no React and no caching here.

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

Never inline key arrays in components or hooks. Invalidate by prefix: `invalidateQueries({ queryKey: orderKeys.all })`.
`orderKeys.all` matches list **and** detail caches, which hold different shapes (`Order[]` vs `Order`), so cache
reads and writes that assume one shape must target `lists()` or `detail(id)`, never `all`.

## 4. Query hooks return what the screen needs

```ts
// features/orders/hooks/useOrdersApi.ts: the feature builds its api from the shared http client
export const useOrdersApi = () => {
  const { http } = useServices();                        // @shared/services/ServicesContext
  return useMemo(() => createOrdersApi(http), [http]);
};

export function useOrders(filter: OrderFilter) {
  const ordersApi = useOrdersApi();
  const q = useQuery({ queryKey: orderKeys.list(filter), queryFn: () => ordersApi.list(filter), staleTime: 30_000 });
  return { orders: q.data ?? [], isLoading: q.isPending, error: q.error as AppError | null, refetch: q.refetch };
}
```

The hook narrows the error to `AppError`; the screen never sees raw `Response` or `AxiosError`.

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
type SessionState = { userId: UserId | null; signIn: (id: UserId) => void; signOut: () => void };
export const useSessionStore = create<SessionState>()((set) => ({
  userId: null, signIn: (userId) => set({ userId }), signOut: () => set({ userId: null }),
}));
// consumers select a slice: const userId = useSessionStore((s) => s.userId);
```

One small store per concern. Never copy server data into a store; the query cache is its owner.

## 7. Offline and retry stance

```ts
// app/providers/QueryProvider.tsx
onlineManager.setEventListener((set) => NetInfo.addEventListener((s) => set(!!s.isConnected)));
const client = new QueryClient({ defaultOptions: { queries: {
  retry: (n, e) => n < 2 && isRetryable(e), networkMode: 'offlineFirst' }, mutations: { retry: 0 } } });
```

- Retry reads only for retryable `AppError`s (network, 5xx). Never retry 4xx.
- Mutations are not retried automatically unless idempotent (send an idempotency key).
- Persist the cache (`@tanstack/react-query-persist-client`) only when the product needs offline reads.

## Do / Don't

- ✅ Validate responses with zod at the api-client edge.
- ✅ One query-key factory per feature; invalidate by prefix.
- ✅ Select narrow Zustand slices to avoid re-renders.
- ❌ `useEffect(() => { fetch(...) }, [])` in a component.
- ❌ Server data mirrored into Zustand or Redux.
- ❌ Several HTTP clients or per-call error handling; map errors once.
- ❌ A global store for state one screen owns; use `useState`.

## Cross-references

- `react-native-code-structure`: where api, hooks and model files live.
- `react-native-error-handling`: `AppError` and `mapHttpError`, used by the client.
- `react-native-input-validation`: shared zod schemas for request and response types.
- `react-native-unit-tests`: testing hooks with MSW and a fresh `QueryClient`.

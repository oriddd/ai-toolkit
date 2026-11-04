---
name: react-native-code-structure
description: Apply the canonical React Native feature-based folder layout, TypeScript strict config, path aliases, dependency direction and naming (screens, components, hooks, services, api) when creating or refactoring an app. Every module is a small single-purpose LEGO brick named so it documents itself. Use when adding a screen, component, hook or feature folder. NOT for server/client state or data fetching (use `react-native-state-and-data`) and NOT for error or validation design (use `react-native-error-handling`, `react-native-input-validation`).
tier: must
applies_to: [mobile]
depends_on: [react-native-state-and-data]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-03
---

# React Native Code Structure Skill
## When to use

Use when creating a screen, component, hook or feature folder, or when refactoring an app whose
files are grouped by technical type (`components/`, `utils/`) instead of by feature.

Every file is a **LEGO brick**: small, single-purpose, independently testable, and named so
that comments are rarely needed (`useCheckoutTotals`, not `useData`).

## Layout

```
src/
├── app/                      # composition root: providers, navigation, bootstrapping
│   ├── App.tsx
│   ├── providers/            # QueryClient, theme, builds the real services and renders ServicesProvider
│   └── navigation/           # typed route maps + navigators
├── features/
│   └── orders/
│       ├── screens/          # OrdersListScreen.tsx  (thin: wires hooks to components)
│       ├── components/       # OrderCard.tsx         (pure render, props in, JSX out)
│       ├── hooks/            # useOrders.ts          (state + behaviour)
│       ├── api/              # ordersApi.ts          (calls the api-client, returns DTOs)
│       ├── model/            # order.ts, orderSchemas.ts (types, zod schemas, mappers)
│       └── index.ts          # public surface of the feature
├── shared/
│   ├── ui/                   # design-system primitives (Button, Text)
│   ├── api-client/           # one HTTP client, interceptors, error mapping
│   ├── services/             # ServicesContext + useServices, storage, analytics, logger: interface + implementation
│   ├── errors/               # AppError hierarchy and message catalogue
│   └── hooks/                # feature-agnostic hooks (useDebounce)
└── test/                     # test utils, MSW handlers, fakes
```

## Dependencies

```json
{ "devDependencies": { "typescript": "^5.6.0", "babel-plugin-module-resolver": "^5.0.0",
  "eslint-plugin-boundaries": "^5.0.0" } }
```

## 1. TypeScript strict and path aliases

```json
// tsconfig.json
{
  "extends": "expo/tsconfig.base",
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitOverride": true,
    "baseUrl": ".",
    "paths": { "@app/*": ["src/app/*"], "@features/*": ["src/features/*"], "@shared/*": ["src/shared/*"] }
  }
}
```

Mirror the aliases in `babel.config.js` (`module-resolver`) so Metro resolves what `tsc` resolves.
Never use `../../../` across feature boundaries; use an alias.

## 2. Dependency direction

```
app  ->  features  ->  shared
```

- `shared` imports nothing from `features` or `app`. Anything both a feature and `shared/errors` need
  (the services context and `useServices`) therefore lives in `shared/services/`, never in `app/`.
- A feature never imports another feature's internals, only its `index.ts`.
- Inside a feature: `screens -> components/hooks -> api -> model`. Never upward.
- Enforce it mechanically (see `react-native-static-analysis`) with `eslint-plugin-boundaries`.

## 3. Screens, components, hooks

```tsx
// features/orders/screens/OrdersListScreen.tsx: thin wiring, no logic
export function OrdersListScreen({ navigation }: OrdersListProps) {
  const { orders, isLoading, error, refetch } = useOrders();
  if (isLoading) return <LoadingState />;
  if (error) return <ErrorState error={error} onRetry={() => void refetch()} />;
  return (
    <OrdersList orders={orders} onSelect={(id) => navigation.navigate('OrderDetail', { id })} />
  );
}
```

```tsx
// features/orders/components/OrderCard.tsx: pure render
type Props = { order: Order; onPress: (id: OrderId) => void };
export const OrderCard = ({ order, onPress }: Props) => (
  <Pressable accessibilityRole="button" testID={`order-card-${order.id}`} onPress={() => onPress(order.id)}>
    <Text>{order.title}</Text>
  </Pressable>
);
```

Rules: components take data and callbacks via props and contain **no data fetching and no business
logic**; behaviour lives in a hook named for what it does. Extract a hook when a component has
more than one `useState`/`useEffect` concern.

## 4. Typed navigation

A feature owns its routes (it cannot import `@app/*`), exports them from its `index.ts`, and `app/` composes them.

```ts
// features/orders/screens/routes.ts
export type OrdersParamList = { OrdersList: undefined; OrderDetail: { id: OrderId } };
// features/orders/index.ts: export type { Order, OrderId } from './model/orderSchemas';
//                           export type { OrdersParamList } from './screens/routes';
```

```ts
// app/navigation/types.ts
import type { OrdersParamList } from '@features/orders'; // the feature's index.ts only, never a deep path
export type RootStackParamList = OrdersParamList;        // several features: OrdersParamList & CartParamList
declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace -- React Navigation types its hooks through this global namespace
  namespace ReactNavigation {
    // eslint-disable-next-line @typescript-eslint/no-empty-object-type -- declaration merging needs an empty interface
    interface RootParamList extends RootStackParamList {}
  }
}
```

The two disables are the only sanctioned ones here (each names its rule and reason, see `react-native-static-analysis`).

Screens receive `NativeStackScreenProps<OrdersParamList, 'OrderDetail'>`. Route params carry
ids, not whole objects; the detail screen reads its data through its own hook.

## 5. Naming

| Thing | Convention | Example |
| --- | --- | --- |
| Component / screen | `PascalCase.tsx`, screen ends `Screen` | `OrderCard.tsx`, `OrdersListScreen.tsx` |
| Hook | `useVerbNoun`, file = hook name | `useCancelOrder.ts` |
| API module | `<feature>Api.ts` | `ordersApi.ts` |
| Types / schemas | `PascalCase` type, `camelCaseSchema` | `Order`, `orderSchema` |
| Test | next to the unit, `*.test.ts(x)` | `OrderCard.test.tsx` |
| Branded ids | `id: z.string().brand<'OrderId'>()` in the schema, `type OrderId = Order['id']` | `OrderId` |

No `utils.ts`, `helpers.ts` or `common.ts` dumping grounds; name the module for its single job
(`formatCurrency.ts`).

## 6. Dependency injection through providers

Infrastructure (API client, storage, analytics) is exposed behind an interface and injected via
context, so tests substitute a fake and the implementation is swappable. The context and hook live in
`shared/` (features and `shared/errors` import them); only the composition root in `app/` builds the real instances.

```tsx
// shared/services/storage/KeyValueStorage.ts
export interface KeyValueStorage { get(key: string): Promise<string | null>; set(key: string, v: string): Promise<void>; }
// shared/services/ServicesContext.tsx: infrastructure only, no feature types
export interface Services { http: HttpClient; storage: KeyValueStorage; logger: Logger; errorReporter: ErrorReporter; }
const ServicesContext = createContext<Services | null>(null);
export const ServicesProvider = ServicesContext.Provider;
export const useServices = (): Services => { const s = useContext(ServicesContext); if (!s) throw new Error('ServicesProvider missing'); return s; };
// app/providers/AppProviders.tsx: <ServicesProvider value={createServices(env)}>...</ServicesProvider>
```

Features build their own api from `useServices().http` in a hook (`useOrdersApi`, see `react-native-state-and-data`).

Smallest pattern that fits: a module-level singleton is fine for a pure function; use a provider
only for things you need to fake or swap.

## Do / Don't

- ✅ Group by feature; keep each file under ~150 lines and single-purpose.
- ✅ Export a feature's public surface from `index.ts` only.
- ✅ Props typed explicitly; no `any`, no non-null `!` without a comment.
- ❌ `fetch`/`axios` or `useQuery` inside a component body.
- ❌ Importing `features/a/hooks/x` from feature `b`.
- ❌ Shared `utils/` or `types/` folders that every feature depends on.
- ❌ Passing whole entities through navigation params.
- ❌ Introducing a pattern (DI container, repository layer) before a second implementation exists.

## Cross-references

- `react-native-state-and-data`: hooks and api layers inside a feature.
- `react-native-error-handling`, `react-native-input-validation`: `shared/errors` and `model/` schemas.
- `react-native-static-analysis`: enforce boundaries and strict TypeScript in CI.
- `react-native-unit-tests`: how to test each brick.

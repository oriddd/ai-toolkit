---
name: react-native-code-structure
description: >
  React Native feature-based layout — TypeScript strict, path aliases, dependency direction, naming for screens,
  components, hooks, services and api. Use before adding a screen, component, hook or feature folder. State and data
  fetching live in `react-native-state-and-data`.
tier: must
applies_to: [mobile]
depends_on: []
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-11
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

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
{ "dependencies": { "@react-navigation/native": "^7.1.0", "@react-navigation/native-stack": "^7.3.0",
  "react-native-screens": "<sdk-matched>", "react-native-safe-area-context": "<sdk-matched>" },
  "devDependencies": { "typescript": ">=5.6 <6.1", "babel-plugin-module-resolver": "^5.0.0",
  "eslint-plugin-boundaries": "^7.4.0" } }
```

`typescript`: use the version your Expo SDK (or React Native template) ships (SDK 58: `~6.0`); `typescript-eslint`
supports TypeScript below 6.1, which sets the upper bound, so never TypeScript 7. Add packages with native code
(`react-native-screens`, `react-native-safe-area-context`) with `npx expo install` so they match the SDK.

## 1. TypeScript strict and path aliases

```json
// tsconfig.json
{
  "extends": "expo/tsconfig.base",   // Expo apps; a bare React Native CLI app extends "@react-native/typescript-config/tsconfig.json"
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitOverride": true,
    "types": ["jest"],                // TypeScript 6 no longer loads every @types package by default
    "paths": { "@app/*": ["./src/app/*"], "@features/*": ["./src/features/*"], "@shared/*": ["./src/shared/*"] }
  }
}
```

`paths` resolve relative to the `tsconfig.json` without `baseUrl`, which TypeScript 6 deprecates (TS5101).
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
// LoadingState and OrdersList are the app's own components (a spinner; a FlatList of OrderCard, testID="orders-list")
type OrdersListProps = NativeStackScreenProps<OrdersParamList, 'OrdersList'>;
const OPEN_ORDERS: OrderFilter = { status: 'open' };    // module constant: OrderFilter, see react-native-state-and-data

export function OrdersListScreen({ navigation }: OrdersListProps) {
  const { orders, isLoading, error, refetch } = useOrders(OPEN_ORDERS);
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
export interface Services { http: HttpClient; storage: KeyValueStorage; logger: Logger; errorReporter: ErrorReporter; analytics: Analytics; }
const ServicesContext = createContext<Services | null>(null);
export const ServicesProvider = ServicesContext.Provider;
export const useServices = (): Services => { const s = useContext(ServicesContext); if (!s) throw new Error('ServicesProvider missing'); return s; };
```

```tsx
// app/providers/AppProviders.tsx: build the services ONCE; a new object per render would re-render every
// consumer and invalidate every useMemo([http]) downstream
export const AppProviders = ({ env, children }: PropsWithChildren<{ env: AppEnv }>) => {
  const [services] = useState(() => createServices(env));
  return <ServicesProvider value={services}>{children}</ServicesProvider>;
};
```

Features build their own api from `useServices().http` in a hook (`useOrdersApi`, see `react-native-state-and-data`).

Smallest pattern that fits: a module-level singleton is fine for a pure function; use a provider
only for things you need to fake or swap.

## 7–8. Accessibility and lists (reference)

Load only the file you need:

| § | Topic | Load when | File |
| --- | --- | --- | --- |
| 7 | Roles, labels, states, touch targets, font scaling | building any interactive component or form field | [accessibility-and-lists.md](./references/accessibility-and-lists.md) |
| 8 | `FlatList` rules, stable keys, pagination, FlashList | rendering a list that can outgrow one screen | [accessibility-and-lists.md](./references/accessibility-and-lists.md) |

Minimum without loading it: every pressable has `accessibilityRole` and a name, inputs have `accessibilityLabel`, and
growing lists are a virtualised `FlatList` keyed by the domain id, never `map` inside a `ScrollView`.

## Do / Don't

- ✅ Group by feature; keep each file under ~150 lines and single-purpose.
- ✅ Export a feature's public surface from `index.ts` only.
- ✅ Props typed explicitly; no `any`, no non-null `!`: narrow instead (`strictTypeChecked` makes `no-non-null-assertion` an error outside tests; an unavoidable one needs an `eslint-disable-next-line` naming the rule and the reason, see `react-native-static-analysis`).
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

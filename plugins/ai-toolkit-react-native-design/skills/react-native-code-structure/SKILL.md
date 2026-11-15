---
name: react-native-code-structure
description: >
  React Native feature-based layout — Expo Router routes, TypeScript strict, path aliases, dependency direction,
  naming for screens, components, hooks and api. Use before adding a screen, route, component, hook or feature folder.
  Data fetching lives in `react-native-state-and-data`.
tier: must
applies_to: [mobile]
depends_on: []
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-15
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# React Native Code Structure Skill
## When to use

Use when creating a screen, component, hook or feature folder, or when refactoring an app whose
files are grouped by technical type (`components/`, `utils/`) instead of by feature.

Every file is a **LEGO brick**: small, single-purpose, independently testable, and named so
that comments are rarely needed (`useCheckoutTotals`, not `useData`).

## Layout

The default is the Expo SDK 58 template: **Expo Router**, with every file in `src/app/` a route. An app that already
uses React Navigation without Expo Router keeps it (section 4b); never migrate navigation unasked.

```
src/
├── app/                      # Expo Router routes ONLY: every file here becomes a screen
│   ├── _layout.tsx           # root layout: initSentry, <AppProviders>, <Stack />
│   ├── index.tsx             # e.g. <Redirect href="/orders" />
│   └── orders/
│       ├── index.tsx         # export { OrdersListScreen as default } from '@features/orders';
│       └── [id].tsx          # export { OrderDetailScreen as default } from '@features/orders';
├── bootstrap/                # composition root: env, createServices, AppProviders, QueryProvider
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
{ "main": "expo-router/entry",
  "dependencies": { "expo-router": "<sdk-matched>", "react-native-screens": "<sdk-matched>",
  "react-native-safe-area-context": "<sdk-matched>" },
  "devDependencies": { "typescript": ">=5.6 <6.1", "babel-plugin-module-resolver": "^5.0.0",
  "eslint-plugin-boundaries": "^7.4.0" } }
```

`app.json`: `"plugins": ["expo-router"]` and `"experiments": { "typedRoutes": true }` (both in the SDK 58 template).
Expo Router 58 bundles its own copy of React Navigation: do not add `@react-navigation/*` to an Expo Router app.
React Navigation apps (section 4b) take `@react-navigation/native` `^7.1.0` and `@react-navigation/native-stack` `^7.3.0` instead.

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
    "paths": { "@bootstrap/*": ["./src/bootstrap/*"], "@features/*": ["./src/features/*"], "@shared/*": ["./src/shared/*"] }
  },
  "include": ["**/*.ts", "**/*.tsx", ".expo/types/**/*.ts", "expo-env.d.ts"]   // typed routes live in .expo/types
}
```

`paths` resolve relative to the `tsconfig.json` without `baseUrl`, which TypeScript 6 deprecates (TS5101).
Mirror the aliases in `babel.config.js` (`module-resolver`) so Metro resolves what `tsc` resolves.
Never use `../../../` across feature boundaries; use an alias. Routes are not imported by anything, so `src/app` has no
alias. (A React Navigation app keeps its composition root in `src/app/` with an `@app/*` alias instead of `bootstrap`.)

## 2. Dependency direction

```
app (routes)  ->  bootstrap  ->  features  ->  shared
```

- Route files hold no logic: they re-export a feature screen as `default` (or render it), and only `_layout.tsx`
  imports `bootstrap`. Screens, hooks and components live in features, where they can be unit-tested.
- `shared` imports nothing from `features`, `bootstrap` or `app`. Anything both a feature and `shared/errors` need
  (the services context and `useServices`) therefore lives in `shared/services/`, never in `bootstrap/`.
- A feature never imports another feature's internals, only its `index.ts`.
- Inside a feature: `screens -> components/hooks -> api -> model`. Never upward; a screen reaches the api only
  through a hook, and components never call hooks that fetch.
- Enforce all of it mechanically (see `react-native-static-analysis`) with `eslint-plugin-boundaries`.

## 3. Screens, components, hooks

```tsx
// features/orders/screens/OrdersListScreen.tsx: thin wiring, no logic
// LoadingState and OrdersList are the app's own components (a spinner; a FlatList of OrderCard, testID="orders-list")
const OPEN_ORDERS: OrderFilter = { status: 'open' };    // module constant: OrderFilter, see react-native-state-and-data

export function OrdersListScreen() {
  const router = useRouter();                           // expo-router
  const { orders, isLoading, error, refetch } = useOrders(OPEN_ORDERS);
  if (isLoading) return <LoadingState />;
  if (error) return <ErrorState error={error} onRetry={() => void refetch()} />;
  return (
    <OrdersList orders={orders} onSelect={(id) => router.push({ pathname: '/orders/[id]', params: { id } })} />
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

## 4. Typed routes (Expo Router)

The route tree is the file tree under `src/app/`; `experiments.typedRoutes` generates `.expo/types/router.d.ts` when
`npx expo start` runs, and from then on `tsc` rejects a `pathname` or `href` that is not a route
(`'/order/[id]'` fails with TS2820). The folder is gitignored: without it `tsc` still passes but paths are unchecked.

```tsx
// src/app/_layout.tsx: the root layout is the composition root's only entry
initSentry(env, readAppInfo());                          // react-native-observability §1
export default Sentry.wrap(function RootLayout() {
  return (
    <AppProviders env={env}>                             {/* @bootstrap/AppProviders */}
      <Stack />
    </AppProviders>
  );
});
// src/app/orders/[id].tsx
export { OrderDetailScreen as default } from '@features/orders';
```

Route params arrive as strings from a URL (any deep link can reach any route), so the screen parses them with the
feature's schema before use; never cast them:

```tsx
// features/orders/model/orderSchemas.ts: export const orderRouteParams = z.object({ id: orderSchema.shape.id });
// features/orders/screens/OrderDetailScreen.tsx
export function OrderDetailScreen() {
  const params = orderRouteParams.safeParse(useLocalSearchParams());
  if (!params.success) return <NotFoundState />;
  return <OrderDetail id={params.data.id} />;            // a component with its own useOrder(id) hook
}
```

Route params carry ids, not whole objects; the detail screen reads its data through its own hook.

## 4b. Typed navigation (React Navigation, reference)

Apps without Expo Router keep React Navigation: composition root in `src/app/` (`@app/*`), a feature exports its
`ParamList` from `index.ts`, the global `ReactNavigation.RootParamList` is merged once, and screens take
`NativeStackScreenProps`. Load [react-navigation.md](./references/react-navigation.md) for the code.

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
`shared/` (features and `shared/errors` import them); only the composition root in `bootstrap/` builds the real instances.

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
// bootstrap/AppProviders.tsx (React Navigation apps: app/providers/): build the services ONCE; a new object per render would re-render every
// consumer and invalidate every useMemo([http]) downstream
export const AppProviders = ({ env, children }: PropsWithChildren<{ env: AppEnv }>) => {
  const [services] = useState(() => createServices(env));
  return <ServicesProvider value={services}>{children}</ServicesProvider>;
};
```

Features build their own api from `useServices().http` in a hook (`useOrdersApi`, see `react-native-state-and-data`).

Smallest pattern that fits: a module-level singleton is fine for a pure function; use a provider
only for things you need to fake or swap.

## 7–8. Accessibility, lists and React Navigation (reference)

Load only the file you need:

| § | Topic | Load when | File |
| --- | --- | --- | --- |
| 7 | Roles, labels, states, touch targets, font scaling | building any interactive component or form field | [accessibility-and-lists.md](./references/accessibility-and-lists.md) |
| 8 | `FlatList` rules, stable keys, pagination, FlashList | rendering a list that can outgrow one screen | [accessibility-and-lists.md](./references/accessibility-and-lists.md) |
| 4b | React Navigation param lists, global `RootParamList`, screen props | the app has no Expo Router | [react-navigation.md](./references/react-navigation.md) |

Minimum without loading it: every pressable has `accessibilityRole` and a name, inputs have `accessibilityLabel`, and
growing lists are a virtualised `FlatList` keyed by the domain id, never `map` inside a `ScrollView`.

## Do / Don't

- ✅ Group by feature; keep each file under ~150 lines and single-purpose.
- ✅ Export a feature's public surface from `index.ts` only.
- ✅ Props typed explicitly; no `any`, no non-null `!`: narrow instead (`strictTypeChecked` makes `no-non-null-assertion` an error outside tests; an unavoidable one needs an `eslint-disable-next-line` naming the rule and the reason, see `react-native-static-analysis`).
- ❌ `fetch`/`axios` or `useQuery` inside a component body.
- ❌ Importing `features/a/hooks/x` from feature `b`.
- ❌ Shared `utils/` or `types/` folders that every feature depends on.
- ❌ Passing whole entities through navigation params, or using route params without parsing them.
- ❌ Logic, hooks or providers other than the root layout's in `src/app/` route files.
- ❌ Introducing a pattern (DI container, repository layer) before a second implementation exists.

## Cross-references

- `react-native-state-and-data`: hooks and api layers inside a feature.
- `react-native-error-handling`, `react-native-input-validation`: `shared/errors` and `model/` schemas.
- `react-native-static-analysis`: enforce boundaries and strict TypeScript in CI.
- `react-native-unit-tests`: how to test each brick.

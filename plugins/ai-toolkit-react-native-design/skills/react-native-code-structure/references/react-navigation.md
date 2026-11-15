# React Navigation (apps without Expo Router)

Reference for [`react-native-code-structure`](../SKILL.md) §4b. Load only when the app wires `NavigationContainer`
itself (a bare React Native CLI app, or an Expo app that does not use Expo Router). Expo Router apps use §4 instead.

## 4b. Typed navigation (React Navigation, apps without Expo Router)

A bare React Native CLI app, or an Expo app that already wires `NavigationContainer` itself, keeps React Navigation:
the composition root is `src/app/` (`App.tsx`, `providers/`, `navigation/`, alias `@app/*`) and stands where
`bootstrap` stands in section 2. A feature owns its routes (it cannot import `@app/*`), exports them from its
`index.ts`, and `app/` composes them.

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
Screens receive `NativeStackScreenProps<OrdersParamList, 'OrderDetail'>` and navigate with
`navigation.navigate('OrderDetail', { id })`; route params still carry ids, not whole objects.

# Accessibility and list rendering

Deep dive for [`react-native-code-structure`](../SKILL.md) §7 and §8. Load it when you build an interactive component,
a form field or a list.

## 7. Accessibility

Accessibility is part of a component's contract, and it is what makes the behaviour-first queries of
`react-native-unit-tests` (`getByRole`, `getByLabelText`) work, so it is never a later pass.

| Element | Required |
| --- | --- |
| Anything pressable (`Pressable`, custom buttons, cards) | `accessibilityRole` (`button`, `link`, `tab`, ...) and a name: its visible `Text`, or `accessibilityLabel` for an icon-only control |
| Toggle, checkbox, selected tab, disabled button | `accessibilityState` (`{ checked }`, `{ selected }`, `{ disabled }`) |
| Text input | `accessibilityLabel` equal to the visible label (the `FormTextField` of `react-native-input-validation` sets it from `label`) |
| Error and status messages | `accessibilityRole="alert"` on the container (`ErrorState` in `react-native-error-handling`) |
| Decorative images and icons | `accessible={false}` / `importantForAccessibility="no"` |
| Touch target | at least 44 x 44 pt (iOS) / 48 x 48 dp (Android); extend a small icon with `hitSlop` |

```tsx
// features/orders/components/FavouriteButton.tsx
type Props = { isFavourite: boolean; onToggle: () => void };
export const FavouriteButton = ({ isFavourite, onToggle }: Props) => (
  <Pressable
    accessibilityRole="button"
    accessibilityLabel={isFavourite ? 'Remove from favourites' : 'Add to favourites'}
    accessibilityState={{ selected: isFavourite }}
    hitSlop={12}
    onPress={onToggle}>
    <HeartIcon filled={isFavourite} />
  </Pressable>
);
```

- Labels describe the action or the thing, not the control type ("Add to favourites", not "Heart button").
- Text scales with the system font size: never set `allowFontScaling={false}` on body text; cap extreme sizes with
  `maxFontSizeMultiplier` on dense UI only, and test layouts at the largest size.
- Colour is never the only signal (an error also has text); body text keeps a 4.5:1 contrast ratio.
- Labels and messages come from the same catalogue as visible text, so they are translated with it.

## 8. Lists and rendering performance

```tsx
// features/orders/components/OrdersList.tsx
type Props = { orders: Order[]; onSelect: (id: OrderId) => void };
export const OrdersList = ({ orders, onSelect }: Props) => (
  <FlatList
    testID="orders-list"
    data={orders}
    keyExtractor={(o) => o.id}
    renderItem={({ item }) => <OrderCard order={item} onPress={onSelect} />}
    ListEmptyComponent={<EmptyState message="No orders yet." />}
  />
);
```

- Any list that can grow past one screen is a `FlatList` / `SectionList` (virtualised), never `items.map` inside a
  `ScrollView`. `keyExtractor` returns the stable domain id, never the index.
- The empty state is part of the list (`ListEmptyComponent`), so screens do not branch on `length === 0`.
- Pass stable callbacks and data: `onSelect` takes the id (`OrderCard` calls `onPress(order.id)`), so the row does not
  need a new closure per item. With the React Compiler enabled, do not add `useCallback` / `memo` by hand; without it,
  memoise only what a profile shows re-rendering.
- Paginate server lists with `useInfiniteQuery` and `onEndReached` (see `react-native-state-and-data`); never fetch
  everything and slice on the client.
- Move to `@shopify/flash-list` only when profiling shows `FlatList` is the bottleneck. FlashList 2 runs on the New
  Architecture only (the default since React Native 0.76) and needs no `estimatedItemSize`; install it with
  `npx expo install @shopify/flash-list` so the version matches the SDK.
- Images in lists have fixed dimensions and a cached loader (`expo-image` in Expo apps).
- Measure on a release build on a low-end Android device; dev builds are not representative.

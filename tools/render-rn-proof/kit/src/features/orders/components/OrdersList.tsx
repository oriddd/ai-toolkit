import { FlatList } from 'react-native';
import type { Order, OrderId } from '../model/order';
import { EmptyState } from '@shared/ui/States';
import { OrderCard } from './OrderCard';
export const OrdersList = ({
  orders,
  onSelect,
}: {
  orders: Order[];
  onSelect: (id: OrderId) => void;
}) => (
  <FlatList
    testID="orders-list"
    data={orders}
    keyExtractor={(o) => o.id}
    renderItem={({ item }) => <OrderCard order={item} onPress={onSelect} />}
    ListEmptyComponent={<EmptyState message="No orders yet." />}
  />
);

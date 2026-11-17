import { Pressable, Text } from 'react-native';
import type { Order, OrderId } from '../model/order';
type Props = { order: Order; onPress: (id: OrderId) => void };
export const OrderCard = ({ order, onPress }: Props) => (
  <Pressable
    accessibilityRole="button"
    testID={`order-card-${order.id}`}
    onPress={() => {
      onPress(order.id);
    }}
  >
    <Text>{order.title}</Text>
  </Pressable>
);

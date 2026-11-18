import { Text, View } from 'react-native';
import type { Order } from '../model/order';
export const OrderDetail = ({ order }: { order: Order }) => (
  <View testID="order-detail">
    <Text>{order.title}</Text>
    <Text>{order.status}</Text>
  </View>
);

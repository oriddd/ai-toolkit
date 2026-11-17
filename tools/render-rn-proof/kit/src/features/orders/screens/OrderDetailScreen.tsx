import { useLocalSearchParams } from 'expo-router';
import { ErrorState } from '@shared/errors/ErrorState';
import { LoadingState, NotFoundState } from '@shared/ui/States';
import { OrderDetail } from '../components/OrderDetail';
import { useOrder } from '../hooks/useOrder';
import type { OrderId } from '../model/order';
import { orderRouteParams } from '../model/orderSchemas';
export function OrderDetailScreen() {
  const params = orderRouteParams.safeParse(useLocalSearchParams());
  if (!params.success) return <NotFoundState />;
  return <OrderDetailContent id={params.data.id} />;
}
function OrderDetailContent({ id }: { id: OrderId }) {
  const { order, error, refetch } = useOrder(id);
  if (error) return <ErrorState error={error} onRetry={() => void refetch()} />;
  if (!order) return <LoadingState />;
  return <OrderDetail order={order} />;
}

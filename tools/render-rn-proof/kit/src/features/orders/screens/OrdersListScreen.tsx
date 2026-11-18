import { useRouter } from 'expo-router';
import { ErrorState } from '@shared/errors/ErrorState';
import { LoadingState } from '@shared/ui/States';
import { OrdersList } from '../components/OrdersList';
import { useOrders } from '../hooks/useOrders';
import type { OrderFilter } from '../model/order';
const OPEN_ORDERS: OrderFilter = { status: 'open' };
export function OrdersListScreen() {
  const router = useRouter();
  const { orders, isLoading, error, refetch } = useOrders(OPEN_ORDERS);
  if (isLoading) return <LoadingState />;
  if (error) return <ErrorState error={error} onRetry={() => void refetch()} />;
  return (
    <OrdersList
      orders={orders}
      onSelect={(id) => {
        router.push({ pathname: '/orders/[id]', params: { id } });
      }}
    />
  );
}

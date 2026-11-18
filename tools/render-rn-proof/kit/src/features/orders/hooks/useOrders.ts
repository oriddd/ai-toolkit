import { useQuery } from '@tanstack/react-query';
import type { Order, OrderFilter } from '../model/order';
import { orderKeys } from './orderKeys';
import { useOrdersApi } from './useOrdersApi';
const NO_ORDERS: Order[] = []; // one stable empty array: `?? []` would be new each render

export function useOrders(filter: OrderFilter) {
  const ordersApi = useOrdersApi();
  const q = useQuery({
    queryKey: orderKeys.list(filter),
    queryFn: ({ signal }) => ordersApi.list(filter, signal),
    staleTime: 30_000,
  });
  return {
    orders: q.data ?? NO_ORDERS,
    isLoading: q.isPending,
    isOffline: q.fetchStatus === 'paused', // offline with nothing cached: show it, do not spin
    error: q.error, // AppError | null, via the Register below
    refetch: q.refetch,
  };
}

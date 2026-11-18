import { useQuery } from '@tanstack/react-query';
import type { OrderId } from '../model/order';
import { orderKeys } from './orderKeys';
import { useOrdersApi } from './useOrdersApi';
export function useOrder(id: OrderId) {
  const api = useOrdersApi();
  const q = useQuery({
    queryKey: orderKeys.detail(id),
    queryFn: ({ signal }) => api.get(id, signal),
  });
  return { order: q.data, error: q.error, refetch: q.refetch };
}

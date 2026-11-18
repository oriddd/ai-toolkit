import { useMutation, useQueryClient } from '@tanstack/react-query';
import type { Order } from '../model/order';
import { orderKeys } from './orderKeys';
import { useOrdersApi } from './useOrdersApi';
export function useCancelOrder() {
  const qc = useQueryClient();
  const ordersApi = useOrdersApi();
  return useMutation({
    mutationFn: ordersApi.cancel,
    onMutate: async (id) => {
      await qc.cancelQueries({ queryKey: orderKeys.all });
      const previousLists = qc.getQueriesData<Order[]>({ queryKey: orderKeys.lists() });
      const previousDetail = qc.getQueryData<Order>(orderKeys.detail(id));
      const cancelled = (o: Order): Order => ({ ...o, status: 'cancelled' });
      qc.setQueriesData<Order[]>({ queryKey: orderKeys.lists() }, (old) =>
        old?.map((o) => (o.id === id ? cancelled(o) : o)),
      );
      qc.setQueryData<Order>(orderKeys.detail(id), (old) => (old ? cancelled(old) : old));
      return { previousLists, previousDetail };
    },
    onError: (_e, id, ctx) => {
      ctx?.previousLists.forEach(([key, data]) => qc.setQueryData(key, data));
      qc.setQueryData(orderKeys.detail(id), ctx?.previousDetail); // undefined is a no-op: nothing was cached
    },
    onSettled: () => qc.invalidateQueries({ queryKey: orderKeys.all }),
  });
}

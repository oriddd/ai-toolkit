import type { OrderFilter, OrderId } from '../model/order';
export const orderKeys = {
  all: ['orders'] as const,
  lists: () => [...orderKeys.all, 'list'] as const,
  list: (filter: OrderFilter) => [...orderKeys.lists(), filter] as const,
  detail: (id: OrderId) => [...orderKeys.all, 'detail', id] as const,
};

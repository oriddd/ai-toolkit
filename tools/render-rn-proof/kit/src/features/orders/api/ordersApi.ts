import { z } from 'zod';
import type { HttpClient } from '@shared/api-client/httpClient';
import { orderSchema, type Order, type OrderFilter, type OrderId } from '../model/order';
export const createOrdersApi = (http: HttpClient) => ({
  list: (filter: OrderFilter, signal?: AbortSignal): Promise<Order[]> =>
    http.request(
      { path: '/orders', method: 'GET', query: filter, signal: signal ?? null },
      z.array(orderSchema),
    ),
  get: (id: OrderId, signal?: AbortSignal): Promise<Order> =>
    http.request(
      { path: `/orders/${encodeURIComponent(id)}`, method: 'GET', signal: signal ?? null },
      orderSchema,
    ),
  cancel: (id: OrderId): Promise<Order> =>
    http.request({ path: `/orders/${encodeURIComponent(id)}/cancel`, method: 'POST' }, orderSchema),
});

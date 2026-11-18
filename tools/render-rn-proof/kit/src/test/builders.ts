import { orderSchema } from '@features/orders/model/order';

export const ORDER_ID = '3f2b1c0e-6a5d-4e8f-9b7a-1c2d3e4f5a6b';

export const anOrderDto = (overrides: Partial<{ id: string; title: string; status: string }> = {}) => ({
  id: ORDER_ID,
  title: 'Shoes',
  status: 'open',
  ...overrides,
});

export const anOrder = (overrides: Partial<{ id: string; title: string; status: string }> = {}) =>
  orderSchema.parse(anOrderDto(overrides));

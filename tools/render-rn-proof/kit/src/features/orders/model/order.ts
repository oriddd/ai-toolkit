import { z } from 'zod';
export const orderSchema = z.object({
  id: z.uuid().brand<'OrderId'>(),
  title: z.string(),
  status: z.enum(['open', 'cancelled', 'paid']),
});
export type Order = z.infer<typeof orderSchema>;
export type OrderId = Order['id'];
export type OrderFilter = { status?: Order['status']; customerId?: string };

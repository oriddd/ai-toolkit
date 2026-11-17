import { z } from 'zod';
import type { OrderId } from '@features/orders';
// features/links/model/linkSchemas.ts
export type Route = { name: 'OrderDetail'; params: { id: OrderId } }; // router-neutral target; OrderId from @features/orders
const orderLink = z.object({ orderId: z.uuid().brand<'OrderId'>() }); // same brand as orderSchema's id

const parseUrl = (url: string): URL | null => {
  try {
    return new URL(url);
  } catch {
    return null;
  } // malformed links are untrusted input too
};

export function resolveDeepLink(url: string): Route | null {
  const u = parseUrl(url);
  if (!u || u.protocol !== 'https:' || u.hostname !== 'app.example.com') return null;
  if (u.pathname === '/orders') {
    const p = orderLink.safeParse(Object.fromEntries(u.searchParams));
    return p.success ? { name: 'OrderDetail', params: { id: p.data.orderId } } : null;
  }
  return null;
}

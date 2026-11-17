import { z } from 'zod';
import { orderSchema } from './order';
export const orderRouteParams = z.object({ id: orderSchema.shape.id });

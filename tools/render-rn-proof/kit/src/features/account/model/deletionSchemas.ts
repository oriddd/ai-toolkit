import { z } from 'zod';

export const deletionReceiptSchema = z.object({ requestId: z.string().min(1) });
export type DeletionReceipt = z.infer<typeof deletionReceiptSchema>;

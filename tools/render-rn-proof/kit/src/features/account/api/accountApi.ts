import type { HttpClient } from '@shared/api-client/httpClient';
import { deletionReceiptSchema, type DeletionReceipt } from '../model/deletionSchemas';

export const createAccountApi = (http: HttpClient) => ({
  requestDeletion: (): Promise<DeletionReceipt> =>
    http.request({ path: '/me', method: 'DELETE' }, deletionReceiptSchema),
});

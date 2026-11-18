import { useMemo } from 'react';
import { useServices } from '@shared/services/ServicesContext';
import { createOrdersApi } from '../api/ordersApi';
export const useOrdersApi = () => {
  const { http } = useServices(); // @shared/services/ServicesContext
  return useMemo(() => createOrdersApi(http), [http]);
};

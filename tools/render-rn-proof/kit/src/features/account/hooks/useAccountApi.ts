import { useMemo } from 'react';
import { useServices } from '@shared/services/ServicesContext';
import { createAccountApi } from '../api/accountApi';
export const useAccountApi = () => {
  const { http } = useServices();
  return useMemo(() => createAccountApi(http), [http]);
};

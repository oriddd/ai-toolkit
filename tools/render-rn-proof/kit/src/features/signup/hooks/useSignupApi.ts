import { useMemo } from 'react';
import { useServices } from '@shared/services/ServicesContext';
import { createSignupApi } from '../api/signupApi';

export const useSignupApi = () => {
  const { http } = useServices();
  return useMemo(() => createSignupApi(http), [http]);
};

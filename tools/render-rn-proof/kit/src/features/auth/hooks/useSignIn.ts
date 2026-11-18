import { useMemo } from 'react';
import { useMutation } from '@tanstack/react-query';
import { useServices } from '@shared/services/ServicesContext';
import { useSessionStore } from '@shared/state/useSessionStore';
import { createAuthApi } from '../api/authApi';

export function useSignIn() {
  const { http, secure } = useServices();
  const authApi = useMemo(() => createAuthApi(http), [http]);
  return useMutation({
    mutationFn: authApi.login,
    onSuccess: async ({ accessToken, refreshToken, userId }) => {
      await secure.set('token', accessToken);
      await secure.set('refreshToken', refreshToken);
      useSessionStore.getState().signIn(userId);
    },
  });
}

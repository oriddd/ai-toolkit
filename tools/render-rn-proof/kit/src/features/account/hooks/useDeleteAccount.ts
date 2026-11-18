import { useMutation, useQueryClient } from '@tanstack/react-query';
import { signOut } from '@shared/session/signOut';
import { useServices } from '@shared/services/ServicesContext';
import { useAccountApi } from './useAccountApi';

export function useDeleteAccount() {
  const queryClient = useQueryClient();
  const { secure, consent } = useServices();
  const accountApi = useAccountApi();
  return useMutation({
    mutationFn: accountApi.requestDeletion,
    onSuccess: async () => {
      await signOut(queryClient, secure);
      await consent.reset();
    },
  });
}

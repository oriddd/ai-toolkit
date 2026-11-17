import type { QueryClient } from '@tanstack/react-query';
import type { SecureStore } from '@shared/services/secure-storage/SecureStore';
import { useSessionStore } from '@shared/state/useSessionStore';
// shared/session/signOut.ts: the one sign-out path (sign-out button, failed refresh, 401)
export async function signOut(queryClient: QueryClient, secure: SecureStore): Promise<void> {
  await secure.remove('token');
  await secure.remove('refreshToken');
  queryClient.clear(); // in-memory query and mutation caches
  useSessionStore.getState().signOut(); // every user-scoped Zustand store
  // persisted cache (react-query-persist-client): also `await persister.removeClient()`
}

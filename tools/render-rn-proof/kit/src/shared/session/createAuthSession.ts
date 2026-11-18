import { z } from 'zod';
import type { AuthSession, HttpClient } from '@shared/api-client/httpClient';
import { UnauthorizedError, isAppError } from '@shared/errors/AppError';
import type { SecureStore } from '@shared/services/secure-storage/SecureStore';
// shared/session/createAuthSession.ts
const tokenPairSchema = z.object({
  accessToken: z.string().min(1),
  refreshToken: z.string().min(1),
});

// anonymousHttp: createHttpClient(baseUrl, anonymousSession), so the refresh call never recurses into a refresh
export function createAuthSession(secure: SecureStore, anonymousHttp: HttpClient): AuthSession {
  let inFlight: Promise<string | null> | null = null;

  const exchange = async (refreshToken: string) => {
    try {
      return await anonymousHttp.request(
        { path: '/auth/refresh', method: 'POST', body: { refreshToken } },
        tokenPairSchema,
      );
    } catch (e) {
      if (e instanceof UnauthorizedError || (isAppError(e) && e.code === 'BAD_REQUEST'))
        return null; // session over
      throw e; // offline or 5xx: the request fails retryably, the user stays signed in
    }
  };

  const refreshOnce = async (): Promise<string | null> => {
    const refreshToken = await secure.get('refreshToken');
    if (!refreshToken) return null;
    const pair = await exchange(refreshToken);
    if (!pair) return null;
    await secure.set('token', pair.accessToken);
    await secure.set('refreshToken', pair.refreshToken); // rotated refresh tokens replace the old one
    return pair.accessToken;
  };

  return {
    getToken: () => secure.get('token'),
    refresh: () => {
      inFlight ??= refreshOnce().finally(() => {
        inFlight = null;
      });
      return inFlight;
    },
  };
}

import { http, HttpResponse } from 'msw';
import { anonymousSession, createHttpClient } from '@shared/api-client/httpClient';
import { ServerError } from '@shared/errors/AppError';
import { FakeSecureStore } from '../../test/fakes/FakeSecureStore';
import { server } from '../../test/msw/server';
import { createAuthSession } from './createAuthSession';

const sessionWith = async (refreshToken: string | null) => {
  const secure = new FakeSecureStore();
  await secure.set('token', 'old');
  if (refreshToken) await secure.set('refreshToken', refreshToken);
  return { secure, session: createAuthSession(secure, createHttpClient('https://api.test', anonymousSession)) };
};

describe('createAuthSession', () => {
  it('returns the stored access token', async () => {
    const { session } = await sessionWith('r1');
    await expect(session.getToken()).resolves.toBe('old');
  });

  it('returns null without calling the server when there is no refresh token', async () => {
    let calls = 0;
    server.use(
      http.post('*/auth/refresh', () => {
        calls += 1;
        return HttpResponse.json({});
      }),
    );
    const { session } = await sessionWith(null);
    await expect(session.refresh()).resolves.toBeNull();
    expect(calls).toBe(0);
  });

  it('stores the rotated pair and returns the new access token', async () => {
    server.use(http.post('*/auth/refresh', () => HttpResponse.json({ accessToken: 'a2', refreshToken: 'r2' })));
    const { secure, session } = await sessionWith('r1');
    await expect(session.refresh()).resolves.toBe('a2');
    expect(await secure.get('token')).toBe('a2');
    expect(await secure.get('refreshToken')).toBe('r2');
  });

  it('keeps the tokens and fails retryably when the server is down', async () => {
    server.use(http.post('*/auth/refresh', () => new HttpResponse(null, { status: 503 })));
    const { secure, session } = await sessionWith('r1');
    await expect(session.refresh()).rejects.toBeInstanceOf(ServerError);
    expect(await secure.get('refreshToken')).toBe('r1');
  });

  it('treats a rejected refresh token as the end of the session', async () => {
    server.use(http.post('*/auth/refresh', () => new HttpResponse(null, { status: 400 })));
    const { session } = await sessionWith('r1');
    await expect(session.refresh()).resolves.toBeNull();
  });
});

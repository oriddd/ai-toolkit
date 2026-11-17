import { delay, http, HttpResponse } from 'msw';
import { z } from 'zod';
import { NetworkError, ServerError } from '@shared/errors/AppError';
import { server } from '../../test/msw/server';
import { anonymousSession, createHttpClient, toQueryString, type AuthSession } from './httpClient';

const client = (session: AuthSession = anonymousSession) => createHttpClient('https://api.test', session);
const bearer = (token: string): AuthSession => ({
  getToken: () => Promise.resolve(token),
  refresh: () => Promise.resolve(null),
});

describe('toQueryString', () => {
  it('skips undefined values and encodes the rest', () => {
    expect(toQueryString({ a: 'x y', b: undefined, c: 1 })).toBe('?a=x+y&c=1');
    expect(toQueryString(undefined)).toBe('');
  });
});

describe('createHttpClient', () => {
  it('sends the bearer token, the JSON body and parses the response', async () => {
    let seen: { auth: string | null; body: unknown } = { auth: null, body: null };
    server.use(
      http.post('*/things', async ({ request }) => {
        seen = { auth: request.headers.get('authorization'), body: await request.json() };
        return HttpResponse.json({ ok: true });
      }),
    );
    const out = await client(bearer('tok')).request(
      { path: '/things', method: 'POST', body: { a: 1 } },
      z.object({ ok: z.boolean() }),
    );
    expect(out).toEqual({ ok: true });
    expect(seen).toEqual({ auth: 'Bearer tok', body: { a: 1 } });
  });

  it('resolves a 204 against z.undefined()', async () => {
    server.use(http.delete('*/things', () => new HttpResponse(null, { status: 204 })));
    await expect(client().request({ path: '/things', method: 'DELETE' }, z.undefined())).resolves.toBeUndefined();
  });

  it('turns a body that breaks the schema into a non-retryable UNKNOWN error', async () => {
    server.use(http.get('*/things', () => HttpResponse.json({ ok: 'yes' })));
    await expect(client().request({ path: '/things' }, z.object({ ok: z.boolean() }))).rejects.toMatchObject({
      code: 'UNKNOWN',
      retryable: false,
    });
  });

  it('turns a malformed 2xx body into an UNKNOWN error', async () => {
    server.use(http.get('*/things', () => new HttpResponse('not json', { status: 200 })));
    await expect(client().request({ path: '/things' }, z.unknown())).rejects.toMatchObject({ code: 'UNKNOWN' });
  });

  it('maps a 503 to a retryable ServerError', async () => {
    server.use(http.get('*/things', () => new HttpResponse(null, { status: 503 })));
    const error = await client()
      .request({ path: '/things' }, z.unknown())
      .catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ServerError);
    expect(error).toMatchObject({ retryable: true, status: 503 });
  });

  it('maps a request that exceeds its timeout to a NetworkError', async () => {
    server.use(
      http.get('*/slow', async () => {
        await delay(300);
        return HttpResponse.json({});
      }),
    );
    await expect(client().request({ path: '/slow', timeoutMs: 20 }, z.unknown())).rejects.toBeInstanceOf(NetworkError);
  });

  it('aborts when the caller cancels', async () => {
    server.use(
      http.get('*/slow', async () => {
        await delay(300);
        return HttpResponse.json({});
      }),
    );
    const controller = new AbortController();
    const pending = client().request({ path: '/slow', signal: controller.signal }, z.unknown());
    controller.abort();
    await expect(pending).rejects.toBeInstanceOf(NetworkError);
  });

  it('does not send when the caller signal is already aborted', async () => {
    const controller = new AbortController();
    controller.abort();
    await expect(
      client().request({ path: '/never', signal: controller.signal }, z.unknown()),
    ).rejects.toBeInstanceOf(NetworkError);
  });
});

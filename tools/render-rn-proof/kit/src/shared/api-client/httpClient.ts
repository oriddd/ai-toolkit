import type { z } from 'zod';
import { mapHttpError, toContractError, toNetworkError } from '@shared/errors/mapHttpError';
export type HttpRequest = Omit<RequestInit, 'headers' | 'body'> & {
  path: string;
  query?: Record<string, string | number | boolean | undefined>;
  body?: unknown; // JSON-serialised by the client (POST/PUT/PATCH payloads)
  timeoutMs?: number; // default 15 s
};
export interface HttpClient {
  request<T>(req: HttpRequest, schema: z.ZodType<T>): Promise<T>;
} // input type defaults to unknown: a branded or transformed schema's input differs from its output

export interface AuthSession {
  // implemented in shared/session (react-native-security §1)
  getToken(): Promise<string | null>;
  refresh(): Promise<string | null>; // new access token, or null: the session is over
}
export const anonymousSession: AuthSession = {
  getToken: () => Promise.resolve(null),
  refresh: () => Promise.resolve(null),
};

const DEFAULT_TIMEOUT_MS = 15_000;

export const toQueryString = (query: HttpRequest['query']): string => {
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(query ?? {}))
    if (v !== undefined) params.append(k, String(v));
  const s = params.toString();
  return s ? `?${s}` : '';
};

// one signal for the caller's cancellation (TanStack's `signal`) and our timeout; React Native 0.85 and earlier
// have no AbortSignal.timeout / AbortSignal.any (0.88 has both), so compose by hand
const withTimeout = (outer: AbortSignal | null | undefined, ms: number) => {
  const controller = new AbortController();
  const abort = () => {
    controller.abort();
  };
  const timer = setTimeout(abort, ms);
  if (outer?.aborted) abort();
  else outer?.addEventListener('abort', abort);
  return {
    signal: controller.signal,
    clear: () => {
      clearTimeout(timer);
      outer?.removeEventListener('abort', abort);
    },
  };
};

export const createHttpClient = (baseUrl: string, session: AuthSession): HttpClient => ({
  async request(req, schema) {
    const { path, query, body, signal, timeoutMs = DEFAULT_TIMEOUT_MS, ...init } = req; // ours, not RequestInit fields
    const send = async (token: string | null): Promise<Response> => {
      const timeout = withTimeout(signal, timeoutMs);
      try {
        return await fetch(`${baseUrl}${path}${toQueryString(query)}`, {
          ...init,
          signal: timeout.signal,
          headers: {
            ...(token ? { Authorization: `Bearer ${token}` } : {}),
            'Content-Type': 'application/json',
            Accept: 'application/json',
          },
          ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        });
      } catch (cause: unknown) {
        throw toNetworkError(cause); // offline, timeout and cancellation: retryable NetworkError
      } finally {
        timeout.clear();
      }
    };
    let res = await send(await session.getToken());
    if (res.status === 401) {
      // one refresh (single-flight in the session), one retry
      const fresh = await session.refresh();
      if (fresh) res = await send(fresh);
    }
    if (!res.ok) throw await mapHttpError(res); // see react-native-error-handling (reads the problem body)
    const payload: unknown =
      res.status === 204 // 204 has no body: res.json() would throw
        ? undefined
        : await res.json().catch((cause: unknown) => {
            throw toContractError(cause);
          }); // malformed 2xx body
    const parsed = schema.safeParse(payload); // validate the contract at the edge
    if (!parsed.success) throw toContractError(parsed.error); // a ZodError never escapes: it becomes an AppError here
    return parsed.data;
  },
});

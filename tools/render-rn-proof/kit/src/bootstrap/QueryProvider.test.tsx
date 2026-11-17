import type { QueryClient } from '@tanstack/react-query';
import { NetworkError, NotFoundError, ServerError, UnauthorizedError } from '@shared/errors/AppError';
import { tracked } from '../test/queryClients';
import { createQueryClient } from './QueryProvider';

const setup = () => {
  const errorReporter = { report: jest.fn() };
  const onUnauthorized = jest.fn();
  const client = tracked(createQueryClient({ errorReporter, onUnauthorized }));
  return { client, errorReporter, onUnauthorized };
};

const failing = (client: QueryClient, error: Error, key: string) => {
  let calls = 0;
  const result = client
    .query({
      queryKey: [key],
      queryFn: () => {
        calls += 1;
        return Promise.reject(error);
      },
      retryDelay: 1,
    })
    .catch(() => undefined);
  return { calls: () => calls, result };
};

describe('createQueryClient', () => {
  it('retries a 5xx twice and reports it once', async () => {
    const { client, errorReporter } = setup();
    const run = failing(client, new ServerError(503), 'a');
    await run.result;
    expect(run.calls()).toBe(3);
    expect(errorReporter.report).toHaveBeenCalledTimes(1);
  });

  it('neither retries nor reports a 404', async () => {
    const { client, errorReporter } = setup();
    const run = failing(client, new NotFoundError(), 'b');
    await run.result;
    expect(run.calls()).toBe(1);
    expect(errorReporter.report).not.toHaveBeenCalled();
  });

  it('does not report being offline', async () => {
    const { client, errorReporter } = setup();
    await failing(client, new NetworkError(), 'c').result;
    expect(errorReporter.report).not.toHaveBeenCalled();
  });

  it('calls onUnauthorized with its own client for a 401 from a query, and never reports it', async () => {
    const { client, errorReporter, onUnauthorized } = setup();
    await failing(client, new UnauthorizedError(), 'd').result;
    expect(onUnauthorized).toHaveBeenCalledWith(client);
    expect(errorReporter.report).not.toHaveBeenCalled();
  });

  it('calls onUnauthorized for a 401 from a mutation too, and reports an unexpected mutation error', async () => {
    const { client, errorReporter, onUnauthorized } = setup();
    await client
      .getMutationCache()
      .build(client, { mutationFn: () => Promise.reject(new UnauthorizedError()) })
      .execute(undefined)
      .catch(() => undefined);
    expect(onUnauthorized).toHaveBeenCalledTimes(1);
    await client
      .getMutationCache()
      .build(client, { mutationFn: () => Promise.reject(new ServerError(500)) })
      .execute(undefined)
      .catch(() => undefined);
    expect(errorReporter.report).toHaveBeenCalledTimes(1);
  });
});

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, renderHook, waitFor } from '@testing-library/react-native';
import { http, HttpResponse } from 'msw';
import type { PropsWithChildren } from 'react';
import { ServerError } from '@shared/errors/AppError';
import { ServicesProvider } from '@shared/services/ServicesContext';
import { useSessionStore } from '@shared/state/useSessionStore';
import { server } from '../../../test/msw/server';
import { tracked } from '../../../test/queryClients';
import { fakeServices } from '../../../test/renderWithProviders';
import { useDeleteAccount } from './useDeleteAccount';

const setup = async () => {
  const services = fakeServices();
  await services.secure.set('token', 't');
  await services.secure.set('refreshToken', 'r');
  await services.consent.update({ analytics: true, crashReports: true, push: true });
  useSessionStore.getState().signIn('u-1');
  const client = tracked(new QueryClient());
  client.setQueryData(['orders'], ['secret']);
  const wrapper = ({ children }: PropsWithChildren) => (
    <ServicesProvider value={services}>
      <QueryClientProvider client={client}>{children}</QueryClientProvider>
    </ServicesProvider>
  );
  return { services, client, wrapper };
};

describe('useDeleteAccount', () => {
  afterEach(() => {
    useSessionStore.getState().signOut();
  });

  it('signs out, clears the cache and withdraws every consent after a 202', async () => {
    server.use(http.delete('*/me', () => HttpResponse.json({ requestId: 'req-1' }, { status: 202 })));
    const { services, client, wrapper } = await setup();
    const { result } = await renderHook(() => useDeleteAccount(), { wrapper });
    await act(async () => {
      result.current.mutate();
      await Promise.resolve();
    });
    await waitFor(() => {
      expect(result.current.isSuccess).toBe(true);
    });
    expect(result.current.data).toEqual({ requestId: 'req-1' });
    expect(await services.secure.get('token')).toBeNull();
    expect(client.getQueryData(['orders'])).toBeUndefined();
    expect(useSessionStore.getState().userId).toBeNull();
    expect(services.consent.current()).toEqual({ analytics: false, crashReports: false, push: false });
  });

  it('keeps the session, tokens, cache and consent when the server fails', async () => {
    server.use(http.delete('*/me', () => new HttpResponse(null, { status: 500 })));
    const { services, client, wrapper } = await setup();
    const { result } = await renderHook(() => useDeleteAccount(), { wrapper });
    await act(async () => {
      result.current.mutate();
      await Promise.resolve();
    });
    await waitFor(() => {
      expect(result.current.isError).toBe(true);
    });
    expect(result.current.error).toBeInstanceOf(ServerError);
    expect(await services.secure.get('token')).toBe('t');
    expect(client.getQueryData(['orders'])).toEqual(['secret']);
    expect(useSessionStore.getState().userId).toBe('u-1');
    expect(services.consent.current().analytics).toBe(true);
  });
});

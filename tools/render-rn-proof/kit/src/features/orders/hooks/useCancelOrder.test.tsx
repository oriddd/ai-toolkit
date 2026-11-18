import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, renderHook, waitFor } from '@testing-library/react-native';
import { http, HttpResponse } from 'msw';
import type { PropsWithChildren } from 'react';
import { ServicesProvider } from '@shared/services/ServicesContext';
import { anOrder, anOrderDto } from '../../../test/builders';
import { tracked } from '../../../test/queryClients';
import { server } from '../../../test/msw/server';
import { fakeServices } from '../../../test/renderWithProviders';
import type { Order } from '../model/order';
import { orderKeys } from './orderKeys';
import { useCancelOrder } from './useCancelOrder';

const setup = () => {
  const client = tracked(new QueryClient({ defaultOptions: { queries: { retry: false } } }));
  const order = anOrder();
  client.setQueryData(orderKeys.list({}), [order]);
  client.setQueryData(orderKeys.detail(order.id), order);
  const wrapper = ({ children }: PropsWithChildren) => (
    <ServicesProvider value={fakeServices()}>
      <QueryClientProvider client={client}>{children}</QueryClientProvider>
    </ServicesProvider>
  );
  return { client, order, wrapper };
};

describe('useCancelOrder', () => {
  it('marks the order cancelled in the list and the detail cache while the request is pending', async () => {
    server.use(http.post('*/orders/*/cancel', () => HttpResponse.json(anOrderDto({ status: 'cancelled' }))));
    const { client, order, wrapper } = setup();
    const { result } = await renderHook(() => useCancelOrder(), { wrapper });
    await act(async () => {
      result.current.mutate(order.id);
      await Promise.resolve();
    });
    await waitFor(() => {
      expect(client.getQueryData<Order>(orderKeys.detail(order.id))?.status).toBe('cancelled');
    });
    await waitFor(() => {
      expect(result.current.isSuccess).toBe(true);
    });
  });

  it('rolls the caches back when the request fails', async () => {
    server.use(http.post('*/orders/*/cancel', () => new HttpResponse(null, { status: 409 })));
    const { client, order, wrapper } = setup();
    const { result } = await renderHook(() => useCancelOrder(), { wrapper });
    await act(async () => {
      result.current.mutate(order.id);
      await Promise.resolve();
    });
    await waitFor(() => {
      expect(result.current.isError).toBe(true);
    });
    expect(client.getQueryData<Order>(orderKeys.detail(order.id))?.status).toBe('open');
    expect(client.getQueryData<Order[]>(orderKeys.list({}))?.[0]?.status).toBe('open');
  });
});

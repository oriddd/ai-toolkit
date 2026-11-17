import { renderHook, waitFor } from '@testing-library/react-native';
import { http, HttpResponse } from 'msw';
import { NetworkError } from '@shared/errors/AppError';
import { anOrderDto } from '../../../test/builders';
import { server } from '../../../test/msw/server';
import { testProviders } from '../../../test/renderWithProviders';
import { useOrders } from './useOrders';

describe('useOrders', () => {
  it('returns orders from the API', async () => {
    server.use(http.get('*/orders', () => HttpResponse.json([anOrderDto()])));
    const { result } = await renderHook(() => useOrders({}), { wrapper: testProviders() });
    await waitFor(() => {
      expect(result.current.orders).toHaveLength(1);
    });
  });

  it('sends the filter as query parameters', async () => {
    let status: string | null = null;
    server.use(
      http.get('*/orders', ({ request }) => {
        status = new URL(request.url).searchParams.get('status');
        return HttpResponse.json([]);
      }),
    );
    const { result } = await renderHook(() => useOrders({ status: 'open' }), { wrapper: testProviders() });
    await waitFor(() => {
      expect(result.current.isLoading).toBe(false);
    });
    expect(status).toBe('open');
  });

  it('exposes a retryable NetworkError when offline', async () => {
    server.use(http.get('*/orders', () => HttpResponse.error()));
    const { result } = await renderHook(() => useOrders({}), { wrapper: testProviders() });
    await waitFor(() => {
      expect(result.current.error).toBeInstanceOf(NetworkError);
    });
  });
});

import { renderHook, waitFor } from '@testing-library/react-native';
import { http, HttpResponse } from 'msw';
import { anOrder, anOrderDto, ORDER_ID } from '../../../test/builders';
import { server } from '../../../test/msw/server';
import { testProviders } from '../../../test/renderWithProviders';
import { useOrder } from './useOrder';

describe('useOrder', () => {
  it('returns the order of the given id', async () => {
    server.use(http.get(`*/orders/${ORDER_ID}`, () => HttpResponse.json(anOrderDto({ title: 'Boots' }))));
    const { result } = await renderHook(() => useOrder(anOrder().id), { wrapper: testProviders() });
    await waitFor(() => {
      expect(result.current.order?.title).toBe('Boots');
    });
  });

  it('exposes a NotFoundError for an unknown order', async () => {
    server.use(http.get(`*/orders/${ORDER_ID}`, () => new HttpResponse(null, { status: 404 })));
    const { result } = await renderHook(() => useOrder(anOrder().id), { wrapper: testProviders() });
    await waitFor(() => {
      expect(result.current.error).toMatchObject({ code: 'NOT_FOUND' });
    });
  });
});

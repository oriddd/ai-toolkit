import { Slot } from 'expo-router';
import { renderRouter, screen } from 'expo-router/testing-library';
import { userEvent } from '@testing-library/react-native';
import { http, HttpResponse } from 'msw';
import { anOrderDto, ORDER_ID } from '../../../test/builders';
import { server } from '../../../test/msw/server';
import { testProviders } from '../../../test/renderWithProviders';
import { OrderDetailScreen } from './OrderDetailScreen';
import { OrdersListScreen } from './OrdersListScreen';

const routes = () => {
  const Providers = testProviders();
  return {
    _layout: () => (
      <Providers>
        <Slot />
      </Providers>
    ),
    'orders/index': OrdersListScreen,
    'orders/[id]': OrderDetailScreen,
  };
};

describe('order screens', () => {
  it('opens the order detail when an order card is pressed', async () => {
    server.use(
      http.get('*/orders', () => HttpResponse.json([anOrderDto({ title: 'Shoes' })])),
      http.get(`*/orders/${ORDER_ID}`, () => HttpResponse.json(anOrderDto({ title: 'Shoes' }))),
    );
    await renderRouter(routes(), { initialUrl: '/orders' });
    await userEvent.setup().press(await screen.findByRole('button', { name: /shoes/i }));
    expect(screen).toHavePathname(`/orders/${ORDER_ID}`);
    expect(await screen.findByTestId('order-detail')).toBeOnTheScreen();
  });

  it('shows the error state with a retry when the list fails', async () => {
    server.use(http.get('*/orders', () => new HttpResponse(null, { status: 503 })));
    await renderRouter(routes(), { initialUrl: '/orders' });
    expect(await screen.findByTestId('error-state', undefined, { timeout: 3000 })).toBeOnTheScreen();
  });

  it('shows not-found for a route param that is not an order id', async () => {
    await renderRouter(routes(), { initialUrl: '/orders/not-a-uuid' });
    expect(await screen.findByText('Not found')).toBeOnTheScreen();
  });

  it('shows the error state when the order does not exist', async () => {
    server.use(http.get(`*/orders/${ORDER_ID}`, () => new HttpResponse(null, { status: 404 })));
    await renderRouter(routes(), { initialUrl: `/orders/${ORDER_ID}` });
    expect(await screen.findByTestId('error-state')).toBeOnTheScreen();
  });
});

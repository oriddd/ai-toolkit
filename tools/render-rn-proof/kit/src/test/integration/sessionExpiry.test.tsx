import { QueryClientProvider } from '@tanstack/react-query';
import { userEvent, waitFor } from '@testing-library/react-native';
import { renderRouter, screen } from 'expo-router/testing-library';
import { http, HttpResponse } from 'msw';
import { Text } from 'react-native';
import { RootNavigator } from '@bootstrap/RootNavigator';
import { createAppQueryClient } from '@bootstrap/QueryProvider';
import { anonymousSession, createHttpClient } from '@shared/api-client/httpClient';
import { createAuthSession } from '@shared/session/createAuthSession';
import { ServicesProvider, type Services } from '@shared/services/ServicesContext';
import { useSessionStore } from '@shared/state/useSessionStore';
import { OrdersListScreen } from '@features/orders/screens/OrdersListScreen';
import { SignInScreen } from '@features/auth/screens/SignInScreen';
import { anOrderDto } from '../builders';
import { server } from '../msw/server';
import { fakeServices } from '../renderWithProviders';
import { tracked } from '../queryClients';

const signedInServices = async (): Promise<Services> => {
  const base = fakeServices();
  await base.secure.set('token', 'old');
  await base.secure.set('refreshToken', 'r1');
  const session = createAuthSession(base.secure, createHttpClient('https://api.test', anonymousSession));
  return { ...base, http: createHttpClient('https://api.test', session) };
};

const mount = async (services: Services) => {
  const client = tracked(createAppQueryClient(services));
  client.setQueryData(['orders', 'previous-user'], ['secret']);
  useSessionStore.getState().signIn('u-1');
  await renderRouter(
    {
      _layout: () => (
        <ServicesProvider value={services}>
          <QueryClientProvider client={client}>
            <RootNavigator />
          </QueryClientProvider>
        </ServicesProvider>
      ),
      'orders/index': OrdersListScreen,
      'orders/[id]': () => null,
      'sign-in': SignInScreen,
      'sign-up': () => <Text>sign-up</Text>,
    },
    { initialUrl: '/orders' },
  );
  return client;
};

describe('a 401 ends the session', () => {
  afterEach(() => {
    useSessionStore.getState().signOut();
  });

  it('signs out, clears the cache and redirects to sign-in when a 401 survives the refresh', async () => {
    let refreshCalls = 0;
    server.use(
      http.get('*/orders', () => new HttpResponse(null, { status: 401 })),
      http.post('*/auth/refresh', () => {
        refreshCalls += 1;
        return new HttpResponse(null, { status: 401 });
      }),
    );
    const services = await signedInServices();
    const client = await mount(services);

    await waitFor(() => {
      expect(screen).toHavePathname('/sign-in');
    });
    expect(refreshCalls).toBe(1);
    expect(await services.secure.get('token')).toBeNull();
    expect(client.getQueryData(['orders', 'previous-user'])).toBeUndefined();
    expect(useSessionStore.getState().userId).toBeNull();
  });

  it('keeps the user on the orders list and stores the rotated token when the refresh works', async () => {
    server.use(
      http.get('*/orders', ({ request }) =>
        request.headers.get('authorization') === 'Bearer fresh'
          ? HttpResponse.json([anOrderDto({ title: 'Shoes' })])
          : new HttpResponse(null, { status: 401 }),
      ),
      http.post('*/auth/refresh', () => HttpResponse.json({ accessToken: 'fresh', refreshToken: 'rotated' })),
    );
    const services = await signedInServices();
    await mount(services);

    expect(await screen.findByText('Shoes')).toBeOnTheScreen();
    expect(screen).toHavePathname('/orders');
    expect(await services.secure.get('token')).toBe('fresh');
    expect(await services.secure.get('refreshToken')).toBe('rotated');
  });

  it('lets a signed-out user reach the sign-up screen', async () => {
    const services = await signedInServices();
    await mount(services);
    useSessionStore.getState().signOut();
    await waitFor(() => {
      expect(screen).toHavePathname('/sign-in');
    });
    await userEvent.setup().press(await screen.findByTestId('signin-create-account'));
    expect(await screen.findByText('sign-up')).toBeOnTheScreen();
  });
});

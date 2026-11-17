import { Slot } from 'expo-router';
import { renderRouter, screen } from 'expo-router/testing-library';
import { userEvent, waitFor } from '@testing-library/react-native';
import { http, HttpResponse } from 'msw';
import { Text } from 'react-native';
import { useSessionStore } from '@shared/state/useSessionStore';
import { server } from '../../../test/msw/server';
import { fakeServices, testProviders } from '../../../test/renderWithProviders';
import { SignInScreen } from './SignInScreen';

const routes = (Providers = testProviders()) => ({
  _layout: () => (
    <Providers>
      <Slot />
    </Providers>
  ),
  'sign-in': SignInScreen,
  'sign-up': () => <Text>sign-up page</Text>,
});

const submit = async (email: string, password: string) => {
  const user = userEvent.setup();
  await user.type(screen.getByTestId('signin-email'), email);
  await user.type(screen.getByTestId('signin-password'), password);
  await user.press(screen.getByTestId('signin-submit'));
};

describe('SignInScreen', () => {
  afterEach(() => {
    useSessionStore.getState().signOut();
  });

  it('stores the tokens and signs the session in', async () => {
    server.use(
      http.post('*/auth/login', () =>
        HttpResponse.json({ accessToken: 'a1', refreshToken: 'r1', userId: 'u-1' }),
      ),
    );
    const services = fakeServices();
    await renderRouter(routes(testProviders(services)), { initialUrl: '/sign-in' });
    await submit('a@b.co', 'secret');
    await waitFor(() => {
      expect(useSessionStore.getState().userId).toBe('u-1');
    });
    expect(await services.secure.get('token')).toBe('a1');
    expect(await services.secure.get('refreshToken')).toBe('r1');
    expect(useSessionStore.getState().userId).toBe('u-1');
  });

  it('shows the error state for rejected credentials and stays signed out', async () => {
    server.use(http.post('*/auth/login', () => new HttpResponse(null, { status: 401 })));
    await renderRouter(routes(), { initialUrl: '/sign-in' });
    await submit('a@b.co', 'wrong');
    expect(await screen.findByTestId('error-state')).toBeOnTheScreen();
    expect(useSessionStore.getState().userId).toBeNull();
  });

  it('validates before sending', async () => {
    await renderRouter(routes(), { initialUrl: '/sign-in' });
    await submit('not-an-email', 'secret');
    expect(await screen.findByText('Enter a valid email address.')).toBeOnTheScreen();
  });

  it('links to the sign-up screen', async () => {
    await renderRouter(routes(), { initialUrl: '/sign-in' });
    await userEvent.setup().press(screen.getByTestId('signin-create-account'));
    expect(await screen.findByText('sign-up page')).toBeOnTheScreen();
  });
});

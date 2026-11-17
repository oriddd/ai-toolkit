import { Slot } from 'expo-router';
import { renderRouter, screen } from 'expo-router/testing-library';
import { userEvent } from '@testing-library/react-native';
import { http, HttpResponse } from 'msw';
import { Text } from 'react-native';
import { server } from '../../../test/msw/server';
import { testProviders } from '../../../test/renderWithProviders';
import { SignupScreen } from './SignupScreen';

const routes = () => {
  const Providers = testProviders();
  return {
    _layout: () => (
      <Providers>
        <Slot />
      </Providers>
    ),
    'sign-up': SignupScreen,
    'sign-in': () => <Text>sign-in page</Text>,
  };
};

const fill = async (email: string, password: string, confirm: string) => {
  const user = userEvent.setup();
  await user.type(screen.getByTestId('signup-email'), email);
  await user.type(screen.getByTestId('signup-password'), password);
  await user.type(screen.getByTestId('signup-confirm-password'), confirm);
  await user.press(screen.getByTestId('signup-submit'));
};

describe('SignupScreen', () => {
  it('creates the account and returns to sign-in', async () => {
    let body: unknown = null;
    server.use(
      http.post('*/signup', async ({ request }) => {
        body = await request.json();
        return new HttpResponse(null, { status: 204 });
      }),
    );
    await renderRouter(routes(), { initialUrl: '/sign-up' });
    await fill('a@b.co', 'longenough12', 'longenough12');
    expect(await screen.findByText('sign-in page')).toBeOnTheScreen();
    expect(body).toEqual({ email: 'a@b.co', password: 'longenough12' });
  });

  it('shows the validation messages and sends nothing for an invalid form', async () => {
    await renderRouter(routes(), { initialUrl: '/sign-up' });
    await fill('a@b.co', 'short', 'other');
    expect(await screen.findByText('Use at least 12 characters.')).toBeOnTheScreen();
    expect(screen.queryByText('sign-in page')).not.toBeOnTheScreen();
  });

  it('maps a server field error into the form', async () => {
    server.use(
      http.post('*/signup', () =>
        HttpResponse.json({ errors: [{ field: 'body.email', code: 'value_error' }] }, { status: 422 }),
      ),
    );
    await renderRouter(routes(), { initialUrl: '/sign-up' });
    await fill('a@b.co', 'longenough12', 'longenough12');
    expect(await screen.findByText('Enter a valid email address.')).toBeOnTheScreen();
  });

  it('falls back to the server rejected message for an unmapped code', async () => {
    server.use(
      http.post('*/signup', () =>
        HttpResponse.json({ errors: [{ field: 'body.password', code: 'weird' }] }, { status: 422 }),
      ),
    );
    await renderRouter(routes(), { initialUrl: '/sign-up' });
    await fill('a@b.co', 'longenough12', 'longenough12');
    expect(await screen.findByText('This value was not accepted.')).toBeOnTheScreen();
  });

  it('shows a form-level message when no rendered field matches', async () => {
    server.use(
      http.post('*/signup', () =>
        HttpResponse.json({ errors: [{ field: 'body.nickname', code: 'missing' }] }, { status: 422 }),
      ),
    );
    await renderRouter(routes(), { initialUrl: '/sign-up' });
    await fill('a@b.co', 'longenough12', 'longenough12');
    expect(await screen.findByText('Some of the information is not valid.')).toBeOnTheScreen();
  });

  it('leaves other failures to the banner and stays on the form', async () => {
    server.use(http.post('*/signup', () => new HttpResponse(null, { status: 500 })));
    await renderRouter(routes(), { initialUrl: '/sign-up' });
    await fill('a@b.co', 'longenough12', 'longenough12');
    expect(await screen.findByTestId('signup-submit')).toBeOnTheScreen();
    expect(screen.queryByText('sign-in page')).not.toBeOnTheScreen();
  });
});

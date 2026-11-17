import * as Sentry from '@sentry/react-native';
import { initSentry } from './initSentry';

const env = { name: 'production', apiBaseUrl: 'https://api.example.com', sentryDsn: 'https://k@o.ingest.sentry.io/1' } as const;
const app = { appId: 'com.example.shop', version: '1.0.0', buildNumber: '7' };

const lastOptions = () => {
  const calls = jest.mocked(Sentry.init).mock.calls;
  const options = calls[calls.length - 1]?.[0];
  if (!options) throw new Error('Sentry.init was not called');
  return options;
};

describe('initSentry', () => {
  it('sets release and dist from the binary and samples production traces', () => {
    initSentry(env, app, () => true);
    expect(lastOptions()).toMatchObject({
      dsn: env.sentryDsn,
      environment: 'production',
      release: 'com.example.shop@1.0.0+7',
      dist: '7',
      tracesSampleRate: 0.1,
    });
  });

  it('samples every trace outside production and omits the release without app info', () => {
    initSentry({ ...env, name: 'staging' }, null, () => true);
    const options = lastOptions();
    expect(options.tracesSampleRate).toBe(1);
    expect(options).not.toHaveProperty('release');
  });

  it('drops events, transactions and breadcrumbs while crash reports are not allowed', () => {
    initSentry(env, app, () => false);
    const options = lastOptions();
    expect(options.beforeSend?.({ type: undefined, message: 'x' }, {})).toBeNull();
    expect(options.beforeSendTransaction?.({ type: 'transaction', message: 'x' }, {})).toBeNull();
    expect(options.beforeBreadcrumb?.({ message: 'x' })).toBeNull();
  });

  it('scrubs what it sends once crash reports are allowed', () => {
    initSentry(env, app, () => true);
    const options = lastOptions();
    expect(options.beforeSend?.({ type: undefined, message: 'mail a@b.co' }, {})).toEqual(expect.objectContaining({ message: 'mail [email]' }));
    expect(options.beforeSendTransaction?.({ type: 'transaction', message: 'mail a@b.co' }, {})).toEqual(expect.objectContaining({ message: 'mail [email]' }));
    expect(options.beforeBreadcrumb?.({ message: 'a@b.co' })).toEqual({ message: '[email]' });
  });
});

import * as Sentry from '@sentry/react-native';
import { NetworkError } from '@shared/errors/AppError';
import { createSentryErrorReporter } from './SentryErrorReporter';

describe('createSentryErrorReporter', () => {
  it('tags an AppError by its code and attaches the context', () => {
    createSentryErrorReporter().report(new NetworkError(), { screen: 'orders' });
    expect(Sentry.captureException).toHaveBeenCalledWith(expect.any(NetworkError), {
      extra: { screen: 'orders' },
      tags: { code: 'NETWORK_OFFLINE' },
    });
  });

  it('sends a foreign error without tags', () => {
    const error = new Error('boom');
    createSentryErrorReporter().report(error);
    expect(Sentry.captureException).toHaveBeenLastCalledWith(error, {});
  });
});

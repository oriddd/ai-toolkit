import * as Sentry from '@sentry/react-native';
import { isAppError } from '@shared/errors/AppError';
import type { ErrorReporter } from '@shared/errors/reportError';
export const createSentryErrorReporter = (): ErrorReporter => ({
  report: (error, context) =>
    Sentry.captureException(error, {
      ...(context && { extra: context }), // conditional spread: exactOptionalPropertyTypes
      ...(isAppError(error) && { tags: { code: error.code } }), // forbids passing `undefined` for an optional key
    }),
});

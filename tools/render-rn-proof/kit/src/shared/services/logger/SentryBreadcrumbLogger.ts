import type * as Sentry from '@sentry/react-native';
import type { Logger } from './Logger';
export const createLogger = (sink: Pick<typeof Sentry, 'addBreadcrumb'>): Logger => ({
  info: (message, ctx) => {
    sink.addBreadcrumb({ level: 'info', message, ...(ctx && { data: ctx }) });
  },
  error: (message, ctx) => {
    sink.addBreadcrumb({ level: 'error', message, ...(ctx && { data: ctx }) });
  },
  debug: (message, ctx) => {
    sink.addBreadcrumb({ level: 'debug', message, ...(ctx && { data: ctx }) });
  },
  warn: (message, ctx) => {
    sink.addBreadcrumb({ level: 'warning', message, ...(ctx && { data: ctx }) });
  },
});

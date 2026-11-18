import type { AppError } from '@shared/errors/AppError';
declare module '@tanstack/react-query' {
  interface Register {
    defaultError: AppError;
  }
}

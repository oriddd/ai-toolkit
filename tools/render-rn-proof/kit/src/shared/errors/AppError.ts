export type ErrorCode =
  | 'NETWORK_OFFLINE'
  | 'UNAUTHORIZED'
  | 'FORBIDDEN'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'VALIDATION_FAILED'
  | 'BAD_REQUEST'
  | 'RATE_LIMITED'
  | 'EMAIL_TAKEN'
  | 'SERVER'
  | 'UNKNOWN';
export class AppError extends Error {
  override name = 'AppError';
  constructor(
    readonly code: ErrorCode,
    readonly retryable: boolean,
    options?: { cause?: unknown },
  ) {
    super(code, options);
  }
}
export class NetworkError extends AppError {
  override name = 'NetworkError';
  constructor(cause?: unknown) {
    super('NETWORK_OFFLINE', true, { cause });
  }
}
export class UnauthorizedError extends AppError {
  override name = 'UnauthorizedError';
  constructor() {
    super('UNAUTHORIZED', false);
  }
}
export class NotFoundError extends AppError {
  override name = 'NotFoundError';
  constructor() {
    super('NOT_FOUND', false);
  }
}
export class ServerError extends AppError {
  override name = 'ServerError';
  constructor(readonly status: number) {
    super('SERVER', true);
  }
}
export type FieldErrors = Record<string, string>;
export class ValidationError extends AppError {
  override name = 'ValidationError';
  constructor(readonly fieldErrors: FieldErrors) {
    super('VALIDATION_FAILED', false);
  }
}
export const isAppError = (e: unknown): e is AppError => e instanceof AppError;

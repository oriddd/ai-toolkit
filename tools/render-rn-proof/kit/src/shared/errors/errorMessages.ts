import { isAppError, type ErrorCode } from './AppError';
export const errorMessages: Record<ErrorCode, string> = {
  NETWORK_OFFLINE: "You're offline. Check your connection and try again.",
  UNAUTHORIZED: 'Your session expired. Please sign in again.',
  FORBIDDEN: "You don't have permission to do that.",
  NOT_FOUND: "We couldn't find what you were looking for.",
  CONFLICT: 'This item was changed elsewhere. Refresh and retry.',
  VALIDATION_FAILED: 'Some of the information is not valid.',
  BAD_REQUEST: 'We could not process that request. Please try again.',
  RATE_LIMITED: 'Too many requests. Please wait a moment and try again.',
  EMAIL_TAKEN: 'An account with this email already exists.',
  SERVER: 'Something went wrong on our side. Please try again.',
  UNKNOWN: 'Something went wrong. Please try again.',
};
export const messageFor = (e: unknown): string => errorMessages[isAppError(e) ? e.code : 'UNKNOWN'];

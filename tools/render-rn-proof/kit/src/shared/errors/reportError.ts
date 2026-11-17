import { useServices } from '@shared/services/ServicesContext';
import { isAppError, type ErrorCode } from './AppError';
export interface ErrorReporter {
  report(error: unknown, context?: Record<string, unknown>): void;
}
export const useErrorReporter = (): ErrorReporter => useServices().errorReporter;
const REPORTED: ReadonlySet<ErrorCode> = new Set(['UNKNOWN', 'SERVER', 'BAD_REQUEST']);
export const isReportable = (e: unknown): boolean => !isAppError(e) || REPORTED.has(e.code);

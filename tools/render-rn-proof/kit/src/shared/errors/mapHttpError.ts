import { z } from 'zod';
import {
  AppError,
  NetworkError,
  NotFoundError,
  ServerError,
  UnauthorizedError,
  ValidationError,
  type ErrorCode,
  type FieldErrors,
} from './AppError';
const SERVER_CODES: ReadonlyMap<string, ErrorCode> = new Map<string, ErrorCode>([
  ['EMAIL_ALREADY_REGISTERED', 'EMAIL_TAKEN'],
  ['ORDER_VERSION_CONFLICT', 'CONFLICT'],
]);
const problemSchema = z.object({
  code: z.string().optional(),
  errors: z.array(z.object({ field: z.string(), code: z.string() })).default([]),
});
type Problem = z.infer<typeof problemSchema>;
const NO_PROBLEM: Problem = { errors: [] };
const readProblem = async (res: Response): Promise<Problem> => {
  const parsed = problemSchema.safeParse(await res.json().catch(() => null));
  return parsed.success ? parsed.data : NO_PROBLEM;
};
const fieldErrorsOf = (problem: Problem): FieldErrors =>
  Object.fromEntries(problem.errors.map((e) => [e.field.replace(/^body\./, ''), e.code]));
export async function mapHttpError(res: Response): Promise<AppError> {
  const problem = await readProblem(res);
  const known = problem.code === undefined ? undefined : SERVER_CODES.get(problem.code);
  if (known && res.status < 500) return new AppError(known, false);
  switch (res.status) {
    case 400:
      return new AppError('BAD_REQUEST', false);
    case 401:
      return new UnauthorizedError();
    case 403:
      return new AppError('FORBIDDEN', false);
    case 404:
      return new NotFoundError();
    case 409:
      return new AppError('CONFLICT', false);
    case 422:
      return new ValidationError(fieldErrorsOf(problem));
    case 429:
      return new AppError('RATE_LIMITED', false);
    default:
      return res.status >= 500 ? new ServerError(res.status) : new AppError('UNKNOWN', false);
  }
}
export const toNetworkError = (cause: unknown) => new NetworkError(cause);
export const toContractError = (cause: unknown) => new AppError('UNKNOWN', false, { cause });

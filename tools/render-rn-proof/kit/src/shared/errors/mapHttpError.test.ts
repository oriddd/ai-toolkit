import { errorMessages } from './errorMessages';
import { mapHttpError } from './mapHttpError';
const res = (status: number, body?: unknown) =>
  new Response(body === undefined ? null : JSON.stringify(body), { status });
describe('mapHttpError', () => {
  it.each([
    [404, 'NOT_FOUND'],
    [418, 'UNKNOWN'],
    [500, 'SERVER'],
    [429, 'RATE_LIMITED'],
  ])('maps %i to %s', async (s, c) => {
    expect((await mapHttpError(res(s))).code).toBe(c);
  });
  it('lets a documented problem code win over the status', async () => {
    expect((await mapHttpError(res(409, { code: 'EMAIL_ALREADY_REGISTERED' }))).code).toBe(
      'EMAIL_TAKEN',
    );
  });
  it('reads 422 field errors without the body. prefix', async () => {
    const e = await mapHttpError(
      res(422, {
        code: 'VALIDATION_FAILED',
        errors: [{ field: 'body.email', code: 'value_error' }],
      }),
    );
    expect(e).toMatchObject({ fieldErrors: { email: 'value_error' } });
  });
  it('has a message for every code', () => {
    expect(Object.values(errorMessages).every(Boolean)).toBe(true);
  });
});

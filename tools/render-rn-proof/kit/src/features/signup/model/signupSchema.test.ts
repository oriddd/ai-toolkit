import { signupSchema } from './signupSchema';

const valid = { email: 'a@b.co', password: 'longenough12', confirmPassword: 'longenough12' };
const messages = (input: object) => {
  const result = signupSchema.safeParse(input);
  return result.success ? [] : result.error.issues.map((i) => i.message);
};

describe('signupSchema', () => {
  it('accepts a valid form and trims the email', () => {
    expect(signupSchema.parse({ ...valid, email: '  a@b.co ' }).email).toBe('a@b.co');
  });

  it('rejects an address without a domain', () => {
    expect(messages({ ...valid, email: 'a@' })).toContain('Enter a valid email address.');
  });

  it.each([
    ['11 characters', 'short1short', 'Use at least 12 characters.'],
    ['no digit', 'longenoughpass', 'Include at least one number.'],
  ])('rejects a password with %s', (_label, password, message) => {
    expect(messages({ ...valid, password, confirmPassword: password })).toContain(message);
  });

  it('accepts exactly 12 characters', () => {
    expect(messages({ ...valid, password: 'abcdefghij12', confirmPassword: 'abcdefghij12' })).toEqual([]);
  });

  it('flags a confirmation that does not match', () => {
    expect(messages({ ...valid, confirmPassword: 'different12345' })).toEqual(['Passwords do not match.']);
  });
});

import { scrubBreadcrumb, scrubEvent } from './scrubPii';

describe('scrubEvent', () => {
  it('drops email, token and query string', () => {
    const event = scrubEvent({
      user: { id: 'u', email: 'a@b.co' },
      request: { url: 'https://x/y?token=1', method: 'GET', headers: { a: 'b' } },
      extra: { token: 't', note: 'a@b.co', count: 2 },
      message: 'hi a@b.co',
      exception: { values: [{ value: 'failed for a@b.co' }, {}] },
    });
    expect(event).toEqual({
      user: { id: 'u' },
      request: { url: 'https://x/y', method: 'GET' },
      extra: { token: '[redacted]', note: '[email]', count: 2 },
      message: 'hi [email]',
      exception: { values: [{ value: 'failed for [email]' }, {}] },
    });
  });

  it('keeps an anonymous user anonymous', () => {
    expect(scrubEvent({ user: { email: 'a@b.co' } })).toEqual({ user: {} });
  });
});

describe('scrubBreadcrumb', () => {
  it('scrubs the message and the data of a breadcrumb', () => {
    expect(scrubBreadcrumb({ message: 'a@b.co', data: { url: 'https://x?a=1', cookie: 'c' } })).toEqual({
      message: '[email]',
      data: { url: 'https://x', cookie: '[redacted]' },
    });
  });

  it('passes a bare breadcrumb through', () => {
    expect(scrubBreadcrumb({ category: 'ui' })).toEqual({ category: 'ui' });
  });
});

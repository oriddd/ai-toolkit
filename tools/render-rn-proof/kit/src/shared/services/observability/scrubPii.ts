import type * as Sentry from '@sentry/react-native';
// shared/services/observability/scrubPii.ts
const SENSITIVE_KEY = /pass|token|secret|auth|cookie|email|phone|address/i;
const EMAIL = /[^\s@]+@[^\s@]+\.[^\s@]+/g;
const scrubText = (s: string) => s.replace(EMAIL, '[email]');
const stripQuery = (url: string) => url.split('?')[0] ?? url; // query strings carry ids, tokens, emails
const redact = (data: Record<string, unknown>) =>
  Object.fromEntries(
    Object.entries(data).map(([k, v]) => [
      k,
      SENSITIVE_KEY.test(k) ? '[redacted]' : typeof v === 'string' ? scrubText(stripQuery(v)) : v,
    ]),
  );

export function scrubEvent<E extends Sentry.Event>(event: E): E {
  if (event.user) event.user = event.user.id === undefined ? {} : { id: event.user.id }; // opaque id only
  if (event.request)
    event.request = {
      // no headers, cookies, body or query string
      ...(event.request.url && { url: stripQuery(event.request.url) }),
      ...(event.request.method && { method: event.request.method }),
    };
  if (event.extra) event.extra = redact(event.extra);
  if (event.message) event.message = scrubText(event.message);
  for (const ex of event.exception?.values ?? []) if (ex.value) ex.value = scrubText(ex.value);
  return event;
}

export const scrubBreadcrumb = (crumb: Sentry.Breadcrumb): Sentry.Breadcrumb => ({
  ...crumb,
  ...(crumb.message && { message: scrubText(crumb.message) }),
  ...(crumb.data && { data: redact(crumb.data) }), // http breadcrumbs carry the URL in data.url
});

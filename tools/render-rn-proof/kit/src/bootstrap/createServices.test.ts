import { createServices } from './createServices';

describe('createServices', () => {
  it('builds every service the app injects, with consent denied by default', () => {
    const services = createServices({ name: 'staging', apiBaseUrl: 'https://api.test', sentryDsn: '' });
    expect(Object.keys(services).sort()).toEqual(
      ['analytics', 'consent', 'errorReporter', 'http', 'logger', 'secure', 'storage'].sort(),
    );
    expect(services.consent.current()).toEqual({ analytics: false, crashReports: false, push: false });
  });

  it('keeps analytics silent until consent is granted', async () => {
    const services = createServices({ name: 'staging', apiBaseUrl: 'https://api.test', sentryDsn: '' });
    services.analytics.setUserId('u-1');
    await services.consent.update({ analytics: true });
    services.analytics.setUserId('u-1');
    expect(services.consent.current().analytics).toBe(true);
  });
});

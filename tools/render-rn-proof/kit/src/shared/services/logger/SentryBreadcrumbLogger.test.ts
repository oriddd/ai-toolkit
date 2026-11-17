import { createLogger } from './SentryBreadcrumbLogger';

describe('createLogger', () => {
  it.each([
    ['debug', 'debug'],
    ['info', 'info'],
    ['warn', 'warning'],
    ['error', 'error'],
  ] as const)('writes %s as a %s breadcrumb with its context', (method, level) => {
    const addBreadcrumb = jest.fn();
    createLogger({ addBreadcrumb })[method]('order_cancelled', { orderId: 'o-1' });
    expect(addBreadcrumb).toHaveBeenCalledWith({ level, message: 'order_cancelled', data: { orderId: 'o-1' } });
  });

  it('omits data when there is no context', () => {
    const addBreadcrumb = jest.fn();
    createLogger({ addBreadcrumb }).info('started');
    expect(addBreadcrumb).toHaveBeenCalledWith({ level: 'info', message: 'started' });
  });
});

import 'react-native-url-polyfill/auto';
import { ORDER_ID } from '../test/builders';
import { redirectSystemPath } from './+native-intent';

describe('redirectSystemPath', () => {
  it('maps an allow-listed link to the order route', () => {
    expect(
      redirectSystemPath({ path: `https://app.example.com/orders?orderId=${ORDER_ID}`, initial: true }),
    ).toBe(`/orders/${ORDER_ID}`);
  });

  it.each(['https://evil.example.net/orders?orderId=' + ORDER_ID, 'https://app.example.com/orders', 'junk'])(
    'ignores %s',
    (path) => {
      expect(redirectSystemPath({ path, initial: false })).toBeNull();
    },
  );
});

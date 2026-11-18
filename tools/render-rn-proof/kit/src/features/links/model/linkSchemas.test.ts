import 'react-native-url-polyfill/auto';
import { resolveDeepLink } from './linkSchemas';
const id = '3f2b1c0e-6a5d-4e8f-9b7a-1c2d3e4f5a6b';
describe('resolveDeepLink', () => {
  it('accepts the allow-listed https link', () => {
    expect(resolveDeepLink(`https://app.example.com/orders?orderId=${id}`)).toEqual({
      name: 'OrderDetail',
      params: { id },
    });
  });
  it.each([
    'http://app.example.com/orders',
    `https://evil.com/orders?orderId=${id}`,
    'https://app.example.com/orders?orderId=x',
    'nonsense',
  ])('rejects %s', (u) => {
    expect(resolveDeepLink(u)).toBeNull();
  });
});

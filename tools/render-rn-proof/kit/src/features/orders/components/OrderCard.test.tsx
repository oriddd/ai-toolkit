import { render, screen, userEvent } from '@testing-library/react-native';
import { anOrder } from '../../../test/builders';
import { OrderCard } from './OrderCard';

describe('OrderCard', () => {
  it('calls onPress with the order id when the card is pressed', async () => {
    const onPress = jest.fn();
    const order = anOrder({ title: 'Shoes' });
    await render(<OrderCard order={order} onPress={onPress} />);
    await userEvent.setup().press(screen.getByRole('button', { name: /shoes/i }));
    expect(onPress).toHaveBeenCalledWith(order.id);
  });
});

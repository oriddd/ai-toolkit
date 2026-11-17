import { render, screen } from '@testing-library/react-native';
import { anOrder } from '../../../test/builders';
import { OrdersList } from './OrdersList';

describe('OrdersList', () => {
  it('renders one card per order', async () => {
    await render(<OrdersList orders={[anOrder({ title: 'Shoes' })]} onSelect={jest.fn()} />);
    expect(screen.getByText('Shoes')).toBeOnTheScreen();
  });

  it('shows the empty state when there are no orders', async () => {
    await render(<OrdersList orders={[]} onSelect={jest.fn()} />);
    expect(screen.getByText('No orders yet.')).toBeOnTheScreen();
  });
});

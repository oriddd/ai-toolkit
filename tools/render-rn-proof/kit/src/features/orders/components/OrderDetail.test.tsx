import { render, screen } from '@testing-library/react-native';
import { anOrder } from '../../../test/builders';
import { OrderDetail } from './OrderDetail';

describe('OrderDetail', () => {
  it('shows title and status under the order-detail test id', async () => {
    await render(<OrderDetail order={anOrder({ title: 'Shoes', status: 'paid' })} />);
    expect(screen.getByTestId('order-detail')).toBeOnTheScreen();
    expect(screen.getByText('Shoes')).toBeOnTheScreen();
    expect(screen.getByText('paid')).toBeOnTheScreen();
  });
});

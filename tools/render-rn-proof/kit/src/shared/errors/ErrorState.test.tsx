import { render, screen, userEvent } from '@testing-library/react-native';
import { NetworkError, UnauthorizedError } from './AppError';
import { ErrorState } from './ErrorState';

describe('ErrorState', () => {
  it('shows the catalogue message and a retry button for a retryable error', async () => {
    const onRetry = jest.fn();
    await render(<ErrorState error={new NetworkError()} onRetry={onRetry} />);
    expect(screen.getByText(/you're offline/i)).toBeOnTheScreen();
    await userEvent.setup().press(screen.getByRole('button', { name: /try again/i }));
    expect(onRetry).toHaveBeenCalledTimes(1);
  });

  it('offers no retry for a non-retryable error', async () => {
    await render(<ErrorState error={new UnauthorizedError()} onRetry={jest.fn()} />);
    expect(screen.queryByRole('button')).not.toBeOnTheScreen();
  });

  it('falls back to the unknown message for a foreign error', async () => {
    await render(<ErrorState error={new Error('boom')} />);
    expect(screen.getByText(/something went wrong/i)).toBeOnTheScreen();
  });
});

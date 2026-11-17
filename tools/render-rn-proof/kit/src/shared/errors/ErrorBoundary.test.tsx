import { Text } from 'react-native';
import { render, screen } from '@testing-library/react-native';
import { ServicesProvider } from '@shared/services/ServicesContext';
import { fakeServices } from '../../test/renderWithProviders';
import { AppErrorBoundary } from './ErrorBoundary';
import { isReportable } from './reportError';
import { NetworkError } from './AppError';

const Crash = (): never => {
  throw new Error('render failed');
};

describe('AppErrorBoundary', () => {
  it('shows the crash screen and reports the render error', async () => {
    const report = jest.fn();
    const services = { ...fakeServices(), errorReporter: { report } };
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
    await render(
      <ServicesProvider value={services}>
        <AppErrorBoundary>
          <Crash />
        </AppErrorBoundary>
      </ServicesProvider>,
    );
    expect(screen.getByText('Something went wrong.')).toBeOnTheScreen();
    expect(report).toHaveBeenCalledTimes(1);
  });

  it('renders its children when nothing fails', async () => {
    await render(
      <ServicesProvider value={fakeServices()}>
        <AppErrorBoundary>
          <Text>fine</Text>
        </AppErrorBoundary>
      </ServicesProvider>,
    );
    expect(screen.getByText('fine')).toBeOnTheScreen();
  });
});

describe('isReportable', () => {
  it('reports unexpected errors only', () => {
    expect(isReportable(new Error('x'))).toBe(true);
    expect(isReportable(new NetworkError())).toBe(false);
  });
});

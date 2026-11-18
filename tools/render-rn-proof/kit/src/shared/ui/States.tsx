import { ActivityIndicator, Text } from 'react-native';

export const LoadingState = () => <ActivityIndicator accessibilityLabel="Loading" />;
export const NotFoundState = () => <Text>Not found</Text>;
export const EmptyState = ({ message }: { message: string }) => <Text>{message}</Text>;

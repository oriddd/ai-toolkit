set -euo pipefail
mkdir -p src/screens src/api
cat > package.json <<'EOF'
{
  "name": "shop-app",
  "version": "0.1.0",
  "private": true,
  "dependencies": { "react": "19.1.0", "react-native": "0.81.4", "@tanstack/react-query": "^5.0.0", "@react-navigation/native": "^7.1.0", "@react-navigation/native-stack": "^7.3.0", "zod": "^4.0.0" },
  "devDependencies": { "typescript": "^5.9.0", "jest": "^29.7.0" }
}
EOF
printf '{ "compilerOptions": { "strict": true, "jsx": "react-native" } }\n' > tsconfig.json
mkdir -p src/navigation src/types
cat > src/api/client.ts <<'EOF'
const BASE_URL = 'https://api.example.com';

export async function apiGet<T>(path: string): Promise<T> {
  const res = await fetch(BASE_URL + path);
  if (!res.ok) throw new Error(`GET ${path} failed: ${res.status}`);
  return (await res.json()) as T;
}

export async function apiSend<T>(method: 'POST' | 'DELETE', path: string, body?: unknown): Promise<T> {
  const res = await fetch(BASE_URL + path, { method, body: body ? JSON.stringify(body) : undefined, headers: { 'Content-Type': 'application/json' } });
  if (!res.ok) throw new Error(`${method} ${path} failed: ${res.status}`);
  return (await res.json()) as T;
}
EOF
cat > src/navigation/RootNavigator.tsx <<'EOF'
import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { LoginScreen } from '../screens/LoginScreen';
import { OrdersScreen } from '../screens/OrdersScreen';

export type RootStackParamList = { Login: undefined; Orders: undefined };
const Stack = createNativeStackNavigator<RootStackParamList>();

export function RootNavigator() {
  return (
    <NavigationContainer>
      <Stack.Navigator>
        <Stack.Screen name="Login" component={LoginScreen} />
        <Stack.Screen name="Orders" component={OrdersScreen} />
      </Stack.Navigator>
    </NavigationContainer>
  );
}
EOF
cat > src/screens/OrdersScreen.tsx <<'EOF'
import React from 'react';
import { Text, View } from 'react-native';

export function OrdersScreen() {
  return (
    <View>
      <Text>Orders</Text>
    </View>
  );
}
EOF
cat > src/screens/LoginScreen.tsx <<'EOF'
import React, { useState } from 'react';
import { Button, Text, TextInput, View } from 'react-native';

export function LoginScreen() {
  const [email, setEmail] = useState('');
  const [error, setError] = useState('');
  const login = async () => {
    const res = await fetch('https://api.example.com/login', { method: 'POST', body: JSON.stringify({ email }) });
    if (!res.ok) setError('Login failed');
  };
  return (
    <View>
      <TextInput value={email} onChangeText={setEmail} />
      {error ? <Text>{error}</Text> : null}
      <Button title="Log in" onPress={login} />
    </View>
  );
}
EOF

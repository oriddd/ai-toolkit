---
name: react-native-permissions-and-push
description: >
  React Native (Expo) runtime permissions and push — ask at point of use, denied vs blocked, permission strings via
  config plugins, expo-notifications token registration, Android channel, server send with receipts. Use when a
  feature needs camera, location, notifications or push.
tier: should
applies_to: [mobile]
depends_on: [react-native-code-structure, react-native-state-and-data, react-native-security]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-15
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# React Native Permissions and Push Skill
## When to use

Use when a feature touches a permission-gated capability (camera, photos, location, contacts, microphone,
notifications) or sends push notifications. The OS asks the user **once** on iOS; a careless first prompt loses the
capability for good, so the app owns when and why it asks.

## Layout

```
app.config.ts                         # config plugins: permission strings, notification channel (react-native-app-config-and-updates)
src/shared/permissions/
└── ensurePermission.ts               # granted / denied / blocked, one implementation for every expo module
src/features/notifications/
├── api/devicesApi.ts                 # PUT /devices/push-token
├── hooks/registerForPush.ts          # channel, permission, Expo push token
├── hooks/usePushRegistration.ts      # sends the token, re-sends on rotation
├── hooks/useNotificationNavigation.ts# tap -> parsed deep link -> route
└── index.ts
src/bootstrap/notificationHandler.ts  # foreground presentation, set once
```

## Dependencies

```json
{ "dependencies": { "expo-notifications": "<sdk-matched>", "expo-device": "<sdk-matched>",
  "expo-constants": "<sdk-matched>", "expo-image-picker": "<sdk-matched>" } }
```

Add with `npx expo install` (SDK 58: `expo-notifications ~58.1.9`, `expo-device ~58.0.5`, `expo-image-picker ~58.0.10`).
Push needs a development build: Expo Go on Android has no remote push since SDK 53. Type-checked on 2026-11-15 with these
versions under the strict `tsconfig` of `react-native-code-structure`.

## 1. Declare permissions in config, never in native files

Each module's config plugin writes the iOS usage string and the Android permission. Write a concrete reason (App
Review rejects "This app needs the camera") and switch off what you do not use: a plugin adds its defaults otherwise
(`expo-image-picker` adds `RECORD_AUDIO` unless `microphonePermission: false`).

```ts
// app.config.ts (inside the returned config)
plugins: [
  ...(config.plugins ?? []),
  ['expo-notifications', { defaultChannel: 'default' }],
  ['expo-image-picker', { cameraPermission: 'Allows you to photograph a receipt for your order.', microphonePermission: false }],
],
android: { ...config.android, package: id, blockedPermissions: ['android.permission.RECORD_AUDIO'] },
```

Check the merged result with `npx expo config --type introspect` (`ios.infoPlist`, `android.permissions`).

## 2. Ask at the point of use, distinguish denied from blocked

Ask only when the user starts the action that needs it (taps "Scan receipt"), after a short in-app explanation
for anything non-obvious; never on app launch. Every expo module returns the same `PermissionResponse`, so one helper
covers them all:

```ts
// shared/permissions/ensurePermission.ts
import type { PermissionResponse } from 'expo';

export type PermissionOutcome = 'granted' | 'denied' | 'blocked';

export async function ensurePermission(
  get: () => Promise<PermissionResponse>,
  request: () => Promise<PermissionResponse>,
): Promise<PermissionOutcome> {
  const current = await get();
  if (current.granted) return 'granted';
  if (!current.canAskAgain) return 'blocked';             // asking again shows nothing: do not call request
  const next = await request();
  if (next.granted) return 'granted';
  return next.canAskAgain ? 'denied' : 'blocked';
}
```

- `granted`: continue. `denied`: keep the feature usable without it (pick from library instead of camera) and offer
  to ask again later. `blocked`: explain and offer **Open settings** (`Linking.openSettings()` from `expo-linking`
  or `react-native`); re-check with `get` when the app returns to the foreground (`AppState` `active`).
- Call it from the feature hook, e.g. `ensurePermission(ImagePicker.getCameraPermissionsAsync, ImagePicker.requestCameraPermissionsAsync)`;
  components only render the outcome. Test the helper with fake `PermissionResponse`s for all three outcomes.
- Never treat a denial as an error to report: it is a user choice, not an `AppError`.

## 3. Push: register the token

```ts
// features/notifications/hooks/registerForPush.ts
import { Platform } from 'react-native';
import Constants from 'expo-constants';
import * as Device from 'expo-device';
import * as Notifications from 'expo-notifications';
import { ensurePermission, type PermissionOutcome } from '@shared/permissions/ensurePermission';

export type PushResult = { outcome: PermissionOutcome | 'unsupported'; token: string | null };

export async function registerForPush(): Promise<PushResult> {
  if (Platform.OS === 'android') {                       // Android 13+: no prompt until a channel exists
    await Notifications.setNotificationChannelAsync('default', {
      name: 'General', importance: Notifications.AndroidImportance.DEFAULT,
    });
  }
  const projectId = Constants.easConfig?.projectId;       // set by app.config extra.eas.projectId
  if (!Device.isDevice || !projectId) return { outcome: 'unsupported', token: null };   // simulators get no token
  const outcome = await ensurePermission(
    () => Notifications.getPermissionsAsync(),
    () => Notifications.requestPermissionsAsync(),
  );
  if (outcome !== 'granted') return { outcome, token: null };
  const { data } = await Notifications.getExpoPushTokenAsync({ projectId });
  return { outcome, token: data };
}
```

```ts
// features/notifications/hooks/usePushRegistration.ts
import { useEffect, useMemo } from 'react';
import { Platform } from 'react-native';
import { useMutation } from '@tanstack/react-query';
import * as Notifications from 'expo-notifications';
import { useServices } from '@shared/services/ServicesContext';
import { createDevicesApi } from '../api/devicesApi';
import { registerForPush } from './registerForPush';

const platform = Platform.OS === 'ios' ? 'ios' : 'android';

export function usePushRegistration() {
  const { http } = useServices();
  const devicesApi = useMemo(() => createDevicesApi(http), [http]);   // api/devicesApi.ts: PUT /devices/push-token
  const mutation = useMutation({
    mutationFn: async () => {
      const result = await registerForPush();
      if (result.token) await devicesApi.register({ token: result.token, platform });
      return result.outcome;
    },
  });
  const { mutate } = mutation;
  useEffect(() => {
    const sub = Notifications.addPushTokenListener(() => { mutate(); });  // tokens rotate: register again
    return () => { sub.remove(); };
  }, [mutate]);
  return { enable: () => { mutate(); }, outcome: mutation.data, isPending: mutation.isPending };
}
```

- Ask for notifications after the user did something that makes them useful ("Notify me when it ships"), not at
  first launch; call `enable()` from there. Register again on every sign-in so the server maps token to user.
- The token is a device credential: send it only to your backend over the authenticated client, never log it, and
  delete it server-side on sign-out (`react-native-security`).

## 4. Receiving and tapping

```ts
// bootstrap/notificationHandler.ts: imported once by the root layout
Notifications.setNotificationHandler({
  handleNotification: () => Promise.resolve({
    shouldShowBanner: true, shouldShowList: true, shouldPlaySound: false, shouldSetBadge: false,
  }),
});
```

`shouldShowAlert` is deprecated: use `shouldShowBanner` / `shouldShowList`. A tap is untrusted input like any deep
link: parse the payload's URL with the same resolver as links (`react-native-security`), never navigate to a raw
string.

```ts
// features/notifications/hooks/useNotificationNavigation.ts: called once in the root layout
export function useNotificationNavigation() {
  const router = useRouter();
  const response = Notifications.useLastNotificationResponse();     // the startup tap included (Expo Router example)
  useEffect(() => {
    if (response?.actionIdentifier !== Notifications.DEFAULT_ACTION_IDENTIFIER) return;   // action buttons: own handler
    const url: unknown = response.notification.request.content.data?.url;
    const route = typeof url === 'string' ? resolveDeepLink(url) : null;   // @features/links
    if (route) router.push({ pathname: '/orders/[id]', params: { id: route.params.id } });
  }, [response, router]);
}
```

## 5. Sending (server side)

The backend sends through the Expo push service (or directly to FCM / APNs with `getDevicePushTokenAsync` tokens if it
already owns those credentials):

- `POST https://exp.host/--/api/v2/push/send`, at most **100** messages per request, with
  `Authorization: Bearer <EXPO_ACCESS_TOKEN>` once push security is enabled for the project (store it as a secret).
- Each message: `to`, `title`, `body`, `data: { url }` (an app link the client parses, §4), `channelId: 'default'` on
  Android, `priority`, `ttl`. No PII or secrets in the payload: lock screens show it.
- The send response holds tickets, not delivery. Fetch receipts later (`/--/api/v2/push/getReceipts`, at most 300
  ids per request, about 15 minutes after sending) and **delete the token on `DeviceNotRegistered`**; retry
  `MessageRateExceeded` with backoff. Node servers use `expo-server-sdk` (`chunkPushNotifications`,
  `getPushNotificationReceiptsAsync`); others call the HTTP API through their own client (`python-external-client`,
  `external-client`).
- Push credentials (APNs key, FCM service account) are per bundle id, so each app variant needs its own
  (`react-native-app-config-and-updates`).

## Do / Don't

- ✅ Permission strings and plugins in `app.config.ts`, with a concrete reason; unused permissions switched off.
- ✅ Ask at the point of use; handle `granted`, `denied` and `blocked` (settings link).
- ✅ Android channel created before the permission request; Expo push token sent to the backend and refreshed on rotation.
- ✅ Notification taps parsed like deep links.
- ❌ Requesting permissions or push on app launch.
- ❌ Calling `request…PermissionsAsync` when `canAskAgain` is false and treating the silent result as a fresh denial.
- ❌ Logging push tokens, or PII in notification payloads.
- ❌ Ignoring push receipts, so dead tokens are sent to forever.

## Cross-references

- `react-native-code-structure`: feature folder, services injection, boundaries.
- `react-native-state-and-data`: the mutation and feature api pattern used for token registration.
- `react-native-security`: deep-link parsing for taps, token handling, sign-out cleanup.
- `react-native-app-config-and-updates`: `app.config.ts` variants and the EAS project id.
- `react-native-unit-tests`: test `ensurePermission` and the hooks with fakes.

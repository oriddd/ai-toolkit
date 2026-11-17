# Universal Links and App Links: server files, app config, verification

`resolveDeepLink` (SKILL.md section 3) only decides what the app does with a URL. Whether the OS hands an `https://`
link to the app at all is decided by two files on your domain and two entries in `app.config.ts`. Without them the link
opens the browser and `+native-intent.tsx` never runs.

## 1. The files on the domain

Both live on the exact host the app resolves (`app.example.com`), over HTTPS with a valid certificate, answer `200`
with no redirect and no authentication, and are fetched by the OS (or its CDN) rather than by the user's browser.

`/.well-known/apple-app-site-association` (no file extension, served as `application/json`):

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["ABCDE12345.com.example.shop"],
        "components": [{ "/": "/orders", "?": { "orderId": "*" } }]
      }
    ]
  }
}
```

`appIDs` is `<Apple Team ID>.<bundle identifier>` of the **production** variant only. Allow-list the same paths
`resolveDeepLink` accepts (`/orders` with an `orderId`): a broader pattern routes links to the app that the app then ignores.

`/.well-known/assetlinks.json`:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.example.shop",
      "sha256_cert_fingerprints": ["14:6D:E9:83:C5:73:06:50:D8:EE:B9:95:2F:34:FC:64:16:A0:83:42:E6:1D:BE:A8:8A:04:96:B2:3F:CF:44:E5"]
    }
  }
]
```

The fingerprint must be the certificate that signs the **installed** app. With Play App Signing that is the *app signing
key* shown in Play Console (Setup, App signing), not the upload key and not the EAS keystore. List the upload or debug
fingerprint as a second entry only for builds you sideload. The example value is a placeholder.

Hosting: in an Expo app put both files under `public/.well-known/` (copied to the web export as is); otherwise serve them from
the web server or CDN of the domain. Make sure the extension-less AASA file gets `Content-Type: application/json` and that
no catch-all route or SPA fallback rewrites `/.well-known/*`.

## 2. `app.config.ts`

Verified links belong to the production variant only: development and preview keep their custom scheme
(`react-native-app-config-and-updates` section 1), which also avoids two installed apps claiming one host.

```ts
const LINK_HOST = 'app.example.com';
// VARIANTS entries gain `links: boolean` (true for production only)

ios: {
  ...config.ios,
  bundleIdentifier: id,
  ...(links && { associatedDomains: [`applinks:${LINK_HOST}`] }),
},
android: {
  ...config.android,
  package: id,
  ...(links && {
    intentFilters: [{
      action: 'VIEW',
      autoVerify: true,
      data: [{ scheme: 'https', host: LINK_HOST, pathPrefix: '/orders' }],
      category: ['BROWSABLE', 'DEFAULT'],
    }],
  }),
},
```

Proved on Expo SDK 58 with `APP_VARIANT=production npx expo prebuild --no-install`: the generated
`ios/<App>/<App>.entitlements` holds `com.apple.developer.associated-domains` = `applinks:app.example.com`, and
`AndroidManifest.xml` holds `<intent-filter android:autoVerify="true">` with `<data android:scheme="https"
android:host="app.example.com" android:pathPrefix="/orders"/>`. With `development` or `preview` neither entry exists.
Changing either field changes the native fingerprint: it needs a store build, not an OTA update.

Keep config, server files and code consistent with a test (`jest-expo`, needs `@types/node` for `readFileSync`):
load `app.config.ts` for `production` and assert that the `associatedDomains` host and the intent filter host are the host
`resolveDeepLink` accepts, that `autoVerify` is `true`, that the AASA `appIDs` end with the bundle id, that its path
component equals the intent filter's `pathPrefix`, and that `assetlinks.json` names the package and a fingerprint of
32 colon-separated hex bytes.

## 3. Verification

| Check | Command |
| --- | --- |
| AASA reachable, right type, no redirect | `curl -sSI https://app.example.com/.well-known/apple-app-site-association` (expect `200`, `application/json`, no `Location`) |
| Apple's CDN has the file (iOS fetches via it) | `curl -sS https://app-site-association.cdn-apple.com/a/v1/app.example.com` (a CDN refresh can take a few hours after a change) |
| assetlinks valid for the package | `curl -sS "https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://app.example.com&relation=delegate_permission/common.handle_all_urls"` |
| Android verification state | `adb shell pm get-app-links com.example.shop` (expect `app.example.com: verified`), re-run with `adb shell pm verify-app-links --re-verify com.example.shop` |
| Android opens the app | `adb shell am start -a android.intent.action.VIEW -d "https://app.example.com/orders?orderId=<uuid>"` |
| iOS opens the app | `xcrun simctl openurl booted "https://app.example.com/orders?orderId=<uuid>"` |
| Rejected links stay ignored | the same commands with another host, a missing `orderId` or an unknown path: the app stays where it is |

Pitfalls that fail silently: typing the link into Safari's address bar or tapping it on a page of the same domain does not open the
app on iOS (use Notes, Messages or `simctl`); a development build signed with another key fails Android verification;
`autoVerify` runs at install, so re-install after fixing `assetlinks.json`; iOS caches the AASA at install and at update.

The Maestro flow for the entry point is in `react-native-e2e-tests`.

Not verifiable without hosting and a device: the OS's actual verification result, the Apple CDN fetch and the app opening.

---
name: react-native-app-config-and-updates
description: >
  React Native (Expo) app config and OTA updates — app.config.ts variants per EAS profile (APP_VARIANT), fingerprint
  runtimeVersion, EAS Update channels and publish workflow, expo-doctor in CI, feature-flag stance. Use when adding an
  environment, changing app.config, or shipping an OTA update.
tier: should
applies_to: [mobile]
depends_on: [react-native-ci]
ships_templates: false
hitl: false
version: 1.0
last_reviewed: 2026-11-15
---

> ⚠️ **Experimental.** Not yet validated on production projects; conventions may change before promotion to stable.

# React Native App Config and Updates Skill
## When to use

Use when an Expo app needs more than one installable environment (dev, preview, production side by side on one
phone), when `app.json` grows logic, when an OTA update is published, or when CI must catch SDK-incompatible
dependencies. A bare React Native CLI app without `expo-updates` uses build flavours / schemes instead; this skill
does not apply to it.

## Layout

```
app.config.ts                 # the only app config: variants, runtimeVersion, updates, plugins
eas.json                      # build profiles: env.APP_VARIANT + channel + environment per profile
.github/workflows/
└── update.yml                # EAS Update publish (manual, per channel)
```

`app.json` either goes away or keeps only static keys; `app.config.ts` receives it as `config` and spreads it.

## Dependencies

```json
{ "dependencies": { "expo-updates": "<sdk-matched>" }, "devDependencies": { "expo-doctor": "<current>" } }
```

`<sdk-matched>`: `npx expo install expo-updates` (SDK 58: `~58.0.22`). `<current>`: pin the latest `expo-doctor`
exactly (checked 2026-11-15: 1.21.8). `eas-cli`: the exact pin from `react-native-ci`; checked against 27.10.0.

## 1. Variants in `app.config.ts`

Each EAS build profile is its own installable app: own name, bundle id / package and URL scheme, so a preview
build never overwrites production on a tester's phone and deep links reach the right app. One env var,
`APP_VARIANT`, selects the variant; an unknown value fails the config instead of silently building production.

```ts
// app.config.ts
import type { ConfigContext, ExpoConfig } from 'expo/config';
import { version } from './package.json';                 // react-native-ci §4: version has one source

const VARIANTS = {
  development: { name: 'Shop (Dev)', id: 'com.example.shop.dev', scheme: 'shop-dev' },
  preview: { name: 'Shop (Preview)', id: 'com.example.shop.preview', scheme: 'shop-preview' },
  production: { name: 'Shop', id: 'com.example.shop', scheme: 'shop' },
} as const;
type Variant = keyof typeof VARIANTS;

const isVariant = (v: string | undefined): v is Variant => v !== undefined && Object.hasOwn(VARIANTS, v);
const raw = process.env.APP_VARIANT as string | undefined;
if (raw !== undefined && !isVariant(raw)) throw new Error(`Unknown APP_VARIANT "${raw}"`);
const variant: Variant = raw ?? 'development';
const { name, id, scheme } = VARIANTS[variant];
const EAS_PROJECT_ID = '<your EAS project id>';

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name,
  slug: 'shop',
  version,
  scheme,
  ios: { ...config.ios, bundleIdentifier: id },
  android: { ...config.android, package: id },
  runtimeVersion: { policy: 'fingerprint' },
  updates: { url: `https://u.expo.dev/${EAS_PROJECT_ID}`, checkAutomatically: 'ON_LOAD', fallbackToCacheTimeout: 0 },
  extra: { ...config.extra, eas: { projectId: EAS_PROJECT_ID }, variant },
});
```

```json
// eas.json (merged with react-native-ci §2)
{ "cli": { "appVersionSource": "remote" },
  "build": {
    "development": { "developmentClient": true, "distribution": "internal",
                     "env": { "APP_VARIANT": "development" }, "environment": "development", "channel": "development" },
    "preview": { "distribution": "internal", "env": { "APP_VARIANT": "preview" }, "environment": "preview", "channel": "preview" },
    "production": { "autoIncrement": true, "env": { "APP_VARIANT": "production" }, "environment": "production", "channel": "production" } } }
```

- Add `app.config.ts` to `tsconfig.json` `include` so `tsc --noEmit` type-checks it against `ExpoConfig`.
- Check every variant before merging a config change: `APP_VARIANT=preview npx expo config --type public`.
- Runtime configuration the JS needs (API base URL, Sentry DSN) stays in `EXPO_PUBLIC_*` variables parsed at startup
  (`react-native-observability` §1, `react-native-security`); never read secrets from `extra`, which ships in the bundle.
- Each variant needs its own store / Firebase / push credentials: they are keyed by bundle id.

## 2. Runtime version: fingerprint

`runtimeVersion: { policy: 'fingerprint' }` hashes everything native: autolinked modules and their versions, config
plugins and the **resolved app config** (name, bundle id, plugins, `extra`). An OTA update only reaches builds with
the same hash, so a JS bundle can never land on a binary missing the native code it calls.

Consequences (checked with `npx expo-updates runtimeversion:resolve --platform ios` on SDK 58):

- The preview and production variants have **different** runtime versions. `eas update` must run with the same
  `APP_VARIANT` as the build it targets; with the wrong one it publishes to a runtime no installed app has, and
  nothing happens, without an error.
- Adding a native module, a config plugin or changing a plugin option changes the hash: that change needs a new
  store build, not an update. The publish workflow in §3 compares before every update (`eas fingerprint:compare`, build id vs local).
- Do not use `appVersion` as policy unless every native change bumps `version`; it relies on discipline, the
  fingerprint does not.

## 3. Publishing updates

One channel per build profile (`eas.json` `channel` above); an update is published to a channel, never to "all".

```yaml
# .github/workflows/update.yml
name: update
on:
  workflow_dispatch:
    inputs:
      channel: { type: choice, options: [preview, production], required: true }
      message: { type: string, required: true }
permissions: { contents: read }
jobs:
  publish:
    runs-on: ubuntu-latest
    environment: ${{ inputs.channel }}                     # production requires approval, as releases do
    env:
      APP_VARIANT: ${{ inputs.channel }}                   # same variant as the build: §2
      CHANNEL: ${{ inputs.channel }}
      MESSAGE: ${{ inputs.message }}                       # free text: reaches the shell only as a variable
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
        with: { node-version-file: .nvmrc, cache: npm }
      - uses: expo/expo-github-action@5273c2136bd09c2a341fe3340d3e767ce5a13015 # v9.0.2
        with: { eas-version: <current>, packager: npm, token: '${{ secrets.EXPO_TOKEN }}' }
      - run: npm ci && npm run verify
      - name: Native fingerprint matches the channel's builds
        run: |
          for platform in ios android; do
            build_id=$(eas build:list --channel "$CHANNEL" --platform "$platform" --status finished --limit 1 --json --non-interactive | jq -r '.[0].id // empty')
            [ -n "$build_id" ] || { echo "no finished $platform build on channel $CHANNEL"; exit 1; }
            eas fingerprint:compare --build-id "$build_id" --environment "$CHANNEL" --json --non-interactive \
              | jq -e '.fingerprint1.hash == .fingerprint2.hash' > /dev/null \
              || { echo "native code differs from $platform build $build_id: ship a store build"; exit 1; }
          done
      - run: eas update --channel "$CHANNEL" --environment "$CHANNEL" --message "$MESSAGE" --non-interactive
```

- The fingerprint step is the gate: `eas fingerprint:compare` only prints a verdict and exits 0 on a difference, so the
  step reads its `--json` output and fails on a hash mismatch. It compares against the newest finished build per
  platform on the channel; a differing hash means the update would reach no installed app, or only older builds.
- Never put `${{ inputs.* }}` or `${{ github.event.* }}` inside a `run:` script: the text is pasted into the shell
  before it runs. Pass it through `env:` and quote the variable, as above.
- `--environment` is required from Expo SDK 55: it loads that EAS environment's variables for the bundle.
- `eas update` bundles on the runner, so the job's `env` reaches `app.config.ts` (unlike a cloud `eas build`, which
  reads `eas.json` `env`).
- Roll out production gradually with `--rollout-percentage 10`, then widen; undo with `eas update:rollback` or
  republish the previous group (`eas update:republish --group <id>`).
- Upload the update's source maps to Sentry for the update's release (`react-native-observability`).
- The OTA scope rules stay those of `react-native-ci` §5: JS and assets only, store-policy changes go through review.

In the app, `checkAutomatically: 'ON_LOAD'` with `fallbackToCacheTimeout: 0` never blocks start-up: the update
downloads in the background and applies on the next launch. Offer an in-app "restart to update" only where users
keep the app open for days, with `useUpdates()` (`isUpdatePending`) and `reloadAsync()` from `expo-updates`.

## 4. SDK compatibility in CI

Native packages must match the Expo SDK; a mismatched minor builds and then crashes at runtime. Add to the `verify`
job in `react-native-ci` §1, after `npm ci`:

```yaml
      - run: npx expo-doctor          # includes `expo install --check`; exits 1 on any failed check
```

Both `npx expo-doctor` and `npx expo install --check` exit 1 on a version mismatch (checked on SDK 58). Fix with
`npx expo install --fix`, never by editing versions by hand. Two of its checks (config schema, React Native Directory) call Expo's servers: behind a TLS-intercepting proxy they fail with
"unable to get local issuer certificate" while the 18 local checks pass; fix the CA trust of the runner, do not skip the command.
A deliberate exception goes in
`package.json` `expo.install.exclude` with a comment in the PR.

## 5. Feature flags

OTA updates are not feature flags: an update cannot be targeted per user and a rollback is all-or-nothing. Put
runtime toggles behind an interface (`FeatureFlags { isEnabled(flag: FlagName): boolean }`, a union of flag names)
in `shared/services`, implemented by your flag provider and injected like the other services
(`react-native-code-structure` §6); fake it in tests. Read flags in hooks, not components; remove a flag (and its
dead branch) once it is fully rolled out. Use a build variant only for things that differ per installation
(endpoints, bundle id), never per user.

## 6. Privacy manifest and verified links

`app.config.ts` also owns two store-facing declarations, each proved by prebuilding the production variant
(`APP_VARIANT=production npx expo prebuild --no-install`) and reading the generated native files:

- `ios.privacyManifests` becomes `ios/<App>/PrivacyInfo.xcprivacy`.
- `ios.associatedDomains` and `android.intentFilters` (production only; development and preview keep their scheme) become the
  entitlement and the `autoVerify` intent filter. The server files and verification commands are in
  `react-native-security` (`references/deep-link-server-setup.md`).

`android.allowBackup: false` (`react-native-security` section 6) is set here too and lands as `android:allowBackup="false"`.

## References

| Topic | Load when | File |
| --- | --- | --- |
| Required-reason API entries, collected data types, scanning dependencies, what prebuild proves | adding an SDK that collects data or touches device APIs, or an App Store privacy rejection | [ios-privacy-manifest.md](./references/ios-privacy-manifest.md) |

## Do / Don't

- ✅ One `app.config.ts`, typed with `ExpoConfig`, one variant per EAS profile selected by `APP_VARIANT`.
- ✅ `runtimeVersion: { policy: 'fingerprint' }`; a native change ships as a build.
- ✅ Publish with `--channel`, `--environment` and the matching `APP_VARIANT`; production behind an approval.
- ✅ `npx expo-doctor` in the PR gate.
- ❌ Hard-coded `runtimeVersion: '1.0.0'` that nobody bumps.
- ❌ An unknown `APP_VARIANT` falling back to production.
- ❌ Secrets in `app.config.ts` / `extra`.
- ❌ `eas update --auto` from a laptop to production.

## Cross-references

- `react-native-ci`: build profiles, release workflow, OTA scope (§5), versioning (§4).
- `react-native-observability`: source maps and release per update.
- `react-native-security`: what may live in `EXPO_PUBLIC_*`; deep-link schemes per variant; universal / app link server files.
- `react-native-permissions-and-push`: push credentials are per bundle id, so per variant.

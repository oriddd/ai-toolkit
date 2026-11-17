#!/usr/bin/env bash
# Maintainer tool: build a fresh Expo SDK 58 TypeScript app from the React Native skills and prove they work together.
#
# What it does, in order (any failing step stops the run with a non-zero exit code):
#   1. creates an app from the Expo default template (npx create-expo-app --template default@sdk-58)
#   2. strips the template with the shell block of react-native-code-structure/references/expo-template-setup.md
#   3. installs the dependencies the skills list (npx expo install for SDK-matched packages)
#   4. renders from the skills' fenced blocks: eslint.config.mjs, .prettierrc.json, .prettierignore, jest.config.js,
#      jest.setup.ts, babel.config.js, tsconfig.json, the package.json scripts and lint-staged, .husky/pre-commit and every
#      .maestro/ flow (tools/render-rn-proof/extract.py)
#   5. copies tools/render-rn-proof/kit: the skills' source snippets with their imports added, plus the tests, the fakes and
#      a tiny sample orders feature (the only hand-written glue: LoadingState, CrashScreen, MemoryStorage, the app.config.ts
#      that merges the variants, privacy manifest and verified links of react-native-app-config-and-updates)
#   6. prettier --write (the skills' snippets are compressed for reading, react-native-static-analysis section 3)
#   7. expo export --platform android, then `npm run verify`: tsc --noEmit (strict), eslint --max-warnings 0, prettier --check,
#      jest --ci --coverage with the coverage thresholds of react-native-unit-tests (85/80/85/85)
#   8. expo prebuild --no-install, one platform per call (ios, then android), APP_VARIANT=production, and checks the generated
#      PrivacyInfo.xcprivacy, the associated-domains entitlement and the autoVerify intent filter
#   9. maestro check-syntax on every file under .maestro/
#  10. reports which skill snippets that name a source file are not verbatim in the rendered app (information, not a failure)
#
# Usage:
#   bash tools/render-rn-proof.sh                    # build in a new temporary directory, keep it
#   bash tools/render-rn-proof.sh --dir /tmp/proof   # build in /tmp/proof (must not exist)
#   bash tools/render-rn-proof.sh --reuse /tmp/proof # re-render skills + kit into an app built earlier, skip create/install
#   bash tools/render-rn-proof.sh --skip-native      # skip expo export, prebuild (faster, no native project generation)
#   bash tools/render-rn-proof.sh --skip-maestro     # skip maestro check-syntax when Maestro is not installed
#
# Needs: node >= 22.22, npm, python3, network access to the npm registry, and maestro (developer-installed, see
# react-native-e2e-tests). Takes a few minutes, mostly npm install. Ends with "GREEN" and exit code 0 only if every step passed.
set -euo pipefail

# `expo install` resolves versions from the SDK's own bundledNativeModules.json offline; online it needs api.expo.dev, which a
# TLS-intercepting proxy breaks ("unable to get local issuer certificate").
export EXPO_OFFLINE=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT="$ROOT/tools/render-rn-proof/kit"
EXTRACT="$ROOT/tools/render-rn-proof/extract.py"

APP=""
REUSE=0
SKIP_NATIVE=0
SKIP_MAESTRO=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) APP="$2"; shift 2 ;;
    --reuse) APP="$2"; REUSE=1; shift 2 ;;
    --skip-native) SKIP_NATIVE=1; shift ;;
    --skip-maestro) SKIP_MAESTRO=1; shift ;;
    -h|--help) sed -n '2,32p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

step() { printf '\n==> %s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing prerequisite: $1" >&2; exit 2; }; }
need node; need npm; need npx; need python3
[ "$SKIP_MAESTRO" = 1 ] || need maestro
node -e 'const [a,b,c]=process.versions.node.split(".").map(Number); process.exit(a>22||(a===22&&(b>22||(b===22&&c>=0)))?0:1)' \
  || { echo "Node >= 22.22 required (lint-staged 17, react-native-ci .nvmrc)" >&2; exit 2; }

if [ "$REUSE" = 1 ]; then
  [ -d "$APP/node_modules" ] || { echo "--reuse needs an app with node_modules: $APP" >&2; exit 2; }
else
  if [ -z "$APP" ]; then APP="$(mktemp -d "${TMPDIR:-/tmp}/rn-proof.XXXXXX")/shopapp"; fi
  [ ! -e "$APP" ] || { echo "$APP already exists" >&2; exit 2; }
  mkdir -p "$(dirname "$APP")"
  step "create the Expo SDK 58 app in $APP"
  (cd "$(dirname "$APP")" && npx --yes create-expo-app@latest "$(basename "$APP")" --template default@sdk-58 --no-install --yes)
  step "strip the template (react-native-code-structure, references/expo-template-setup.md section 1)"
  (cd "$APP" && python3 "$EXTRACT" steps "$ROOT" | bash -euxo pipefail)
  rm -f "$APP/app.json.bak"
fi

cd "$APP"

if [ "$REUSE" = 0 ]; then
  step "install dependencies (the lists of the skills; SDK-matched packages through expo install)"
  npm install --no-audit --no-fund
  npx expo install @react-native-community/netinfo expo-secure-store expo-application expo-constants \
    @sentry/react-native -- --no-audit --no-fund
  npm install --no-audit --no-fund \
    "@tanstack/react-query@^5.59.0" "zustand@^5.0.0" "react-error-boundary@^6.0.0" "react-native-url-polyfill@^4.0.0" \
    "zod@^4.0.0" "react-hook-form@^7.55.0" "@hookform/resolvers@^7.0.0"
  npx expo install jest-expo -- --no-audit --no-fund
  npm install --no-audit --no-fund --save-dev \
    "jest@^30.0.0" "@types/jest@^30.0.0" "@testing-library/react-native@^14.1.0" "test-renderer@~1.3.0" "msw@~2.6.0" \
    "babel-plugin-module-resolver@^5.0.0" "typescript-eslint@^8.72.0" "eslint@^10.0.0" "eslint-plugin-react-hooks@^7.1.0" \
    "eslint-plugin-boundaries@^7.4.0" "eslint-import-resolver-typescript@^4.4.0" "eslint-plugin-testing-library@^7.16.0" \
    "eslint-plugin-jest@^29.0.0" "eslint-config-prettier@^10.1.0" "prettier@^3.3.0" "husky@^9.1.0" "lint-staged@^17.0.0"
fi

step "render configs, scripts and Maestro flows from the skills"
rm -rf src/app src/features src/shared src/bootstrap src/test .maestro
python3 "$EXTRACT" render "$ROOT" "$APP"

step "copy the kit: the skills' source snippets with imports, tests, fakes and the sample feature"
mkdir -p src
cp -R "$KIT/src/." src/
cp "$KIT/app.config.ts" app.config.ts

step "prettier --write (snippets are compressed for reading)"
npx prettier --write . >/dev/null

if [ "$SKIP_NATIVE" = 0 ]; then
  step "expo export --platform android"
  rm -rf dist
  npx expo export --platform android
fi

step "npm run verify (tsc strict, eslint --max-warnings 0, prettier --check, jest with the coverage gate)"
npm run verify

if [ "$SKIP_NATIVE" = 0 ]; then
  for platform in ios android; do
    step "expo prebuild --no-install --platform $platform (APP_VARIANT=production)"
    rm -rf ios android
    APP_VARIANT=production CI=1 npx expo prebuild --no-install --platform "$platform"
    if [ "$platform" = ios ]; then
      manifest="$(find ios -name PrivacyInfo.xcprivacy | head -n1)"
      entitlements="$(find ios -name '*.entitlements' | head -n1)"
      [ -n "$manifest" ] || { echo "FAIL: no PrivacyInfo.xcprivacy generated" >&2; exit 1; }
      grep -q NSPrivacyCollectedDataTypeCrashData "$manifest" || { echo "FAIL: privacy manifest lacks the crash data type" >&2; exit 1; }
      grep -q 'applinks:app.example.com' "$entitlements" || { echo "FAIL: associated domain missing from $entitlements" >&2; exit 1; }
      [ ! -d android ] || { echo "FAIL: --platform ios also generated android/" >&2; exit 1; }
    else
      grep -q 'android:autoVerify="true"' android/app/src/main/AndroidManifest.xml || { echo "FAIL: autoVerify intent filter missing" >&2; exit 1; }
      grep -q 'android:allowBackup="false"' android/app/src/main/AndroidManifest.xml || { echo "FAIL: allowBackup is not false" >&2; exit 1; }
      [ ! -d ios ] || { echo "FAIL: --platform android also generated ios/" >&2; exit 1; }
    fi
  done
  rm -rf ios android
fi

if [ "$SKIP_MAESTRO" = 0 ]; then
  step "maestro check-syntax on every flow and subflow"
  count=0
  while IFS= read -r flow; do
    maestro check-syntax "$flow"
    count=$((count + 1))
  done < <(find .maestro -name '*.yaml' | sort)
  echo "$count Maestro files OK"
fi

step "skill snippets versus the rendered sources"
python3 "$EXTRACT" drift "$ROOT" "$APP"

printf '\nGREEN: the skills rendered into %s and passed every step.\n' "$APP"

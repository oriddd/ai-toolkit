#!/usr/bin/env bash
# SessionStart: inject the React Native routing table only when the project is a React Native app. Always exits 0.
# Detects a "react-native" dependency (a version-like value, so a library's "react-native": "src/index.ts" entry
# field does not match) in the root package.json or one workspace level down (apps/*, packages/*, */).
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
show() { [ -r "$root/hooks/routing.md" ] && cat "$root/hooks/routing.md"; exit 0; }
dep='"react-native"[[:space:]]*:[[:space:]]*"([~^<>=*0-9]|x|latest|next|npm:|workspace:|catalog:)'
for f in "$dir/package.json" "$dir"/*/package.json "$dir"/apps/*/package.json "$dir"/packages/*/package.json; do
  case "$f" in */node_modules/*) continue ;; esac
  [ -f "$f" ] && grep -Eq "$dep" "$f" 2>/dev/null && show
done
exit 0

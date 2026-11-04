#!/usr/bin/env bash
# SessionStart: inject the React Native routing table only when the project is a React Native app. Always exits 0.
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
show() { [ -r "$root/hooks/routing.md" ] && cat "$root/hooks/routing.md"; exit 0; }
if [ -f "$dir/package.json" ] && grep -q '"react-native"' "$dir/package.json" 2>/dev/null; then
  show
fi
exit 0

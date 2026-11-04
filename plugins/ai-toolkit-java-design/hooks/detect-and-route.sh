#!/usr/bin/env bash
# SessionStart: inject the Java routing table only when the project is a Java build. Always exits 0.
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
show() { [ -r "$root/hooks/routing.md" ] && cat "$root/hooks/routing.md"; exit 0; }
for f in pom.xml build.gradle build.gradle.kts settings.gradle settings.gradle.kts; do
  [ -f "$dir/$f" ] && show
done
exit 0

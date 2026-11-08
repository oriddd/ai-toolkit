#!/usr/bin/env bash
# SessionStart: inject the Java routing table only when the project is a Java build. Always exits 0.
# Looks at the project root and one workspace level down (*/, apps/*, packages/*, services/*) for monorepos,
# and also routes in an empty project folder (new-service route).
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
show() { [ -r "$root/hooks/routing.md" ] && cat "$root/hooks/routing.md"; exit 0; }
for d in "$dir" "$dir"/*/ "$dir"/apps/*/ "$dir"/packages/*/ "$dir"/services/*/; do
  d="${d%/}"
  case "$d" in */node_modules|*/node_modules/*|*/target|*/build) continue ;; esac
  [ -d "$d" ] || continue
  for f in pom.xml build.gradle build.gradle.kts settings.gradle settings.gradle.kts; do
    [ -f "$d/$f" ] && show
  done
done
# An empty project (nothing but README/LICENSE/.git/editor files) may be about to become a new service:
# inject the table so its "new service from scratch" route is visible.
[ -d "$dir" ] || exit 0
for e in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
  [ -e "$e" ] || continue
  case "${e##*/}" in
    .git|.gitignore|.gitattributes|.DS_Store|.claude|.idea|.vscode|README*|readme*|LICENSE*|LICENCE*) ;;
    *) exit 0 ;;
  esac
done
show

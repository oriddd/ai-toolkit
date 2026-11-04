#!/usr/bin/env bash
# SessionStart: inject the Python routing table only when the project is a Python project. Always exits 0.
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
show() { [ -r "$root/hooks/routing.md" ] && cat "$root/hooks/routing.md"; exit 0; }
for f in pyproject.toml setup.py setup.cfg Pipfile; do
  [ -f "$dir/$f" ] && show
done
for f in "$dir"/requirements*.txt; do
  [ -f "$f" ] && show
done
exit 0

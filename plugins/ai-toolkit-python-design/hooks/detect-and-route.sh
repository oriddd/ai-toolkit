#!/usr/bin/env bash
# SessionStart: inject the Python routing table only when the project is a Python project. Always exits 0.
# Looks at the project root and one workspace level down (*/, apps/*, packages/*, services/*) for monorepos.
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
show() { [ -r "$root/hooks/routing.md" ] && cat "$root/hooks/routing.md"; exit 0; }
for d in "$dir" "$dir"/*/ "$dir"/apps/*/ "$dir"/packages/*/ "$dir"/services/*/; do
  d="${d%/}"
  case "$d" in */node_modules|*/node_modules/*) continue ;; esac
  [ -d "$d" ] || continue
  for f in pyproject.toml setup.py setup.cfg Pipfile; do
    [ -f "$d/$f" ] && show
  done
  for f in "$d"/requirements*.txt; do
    [ -f "$f" ] || continue
    # at the root a requirements file is enough; one level down (docs/requirements.txt for mkdocs in a
    # Java repo) it counts only next to Python code in that directory or its direct subdirectories
    [ "$d" = "$dir" ] && show
    for py in "$d"/*.py "$d"/*/*.py; do
      [ -f "$py" ] && show
    done
  done
done
exit 0

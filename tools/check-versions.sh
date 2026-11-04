#!/usr/bin/env bash
# Fails when a plugin's content changed since the base ref but its plugin.json "version" did not.
# Claude Code keys its plugin cache on `version`: pushing changes without a bump means installed users
# are told "already at the latest version" and never receive them.
#   bash tools/check-versions.sh [base-ref]     (default: origin/main, then main)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
base="${1:-}"
if [ -z "$base" ]; then
  for c in origin/main origin/master main master; do git rev-parse --verify -q "$c" >/dev/null && { base="$c"; break; }; done
fi
[ -n "$base" ] || { echo "check-versions: no base ref found"; [ -n "${CI:-}" ] && exit 1; echo "(skipped — set CI=1 to make this an error)"; exit 0; }
mb="$(git merge-base "$base" HEAD 2>/dev/null || echo "$base")"
fail=0
for dir in plugins/*/; do
  p="$(basename "$dir")"
  changed="$({ git diff --name-only "$mb" -- "$dir" ':(exclude)'"$dir"'.claude-plugin/plugin.json'; git ls-files --others --exclude-standard -- "$dir"; } | grep -v '\.claude-plugin/plugin\.json$' | head -1)"
  [ -n "$changed" ] || continue
  new="$(python3 -c "import json,sys;print(json.load(open('$dir.claude-plugin/plugin.json')).get('version',''))")"
  old="$(git show "$mb:$dir.claude-plugin/plugin.json" 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin).get('version',''))" 2>/dev/null)"
  [ -n "$old" ] || continue    # new plugin: nothing to compare against
  order="$(python3 -c "
import sys
def v(s):
    try: return tuple(int(x) for x in s.split('-')[0].split('.')[:3])
    except ValueError: return None
o, n = v(sys.argv[1]), v(sys.argv[2])
print('same' if o is None or n is None or o == n else ('down' if n < o else 'up'))" "$old" "$new")"
  if [ "$order" = "same" ]; then
    echo "FAIL: $p changed (e.g. $changed) but version is still $new — bump it in $dir.claude-plugin/plugin.json"; fail=1
  elif [ "$order" = "down" ]; then
    echo "FAIL: $p version went down ($old -> $new) — installed users would never receive it"; fail=1
  fi
done
[ $fail -eq 0 ] && echo "versions OK (against $base)"
exit $fail

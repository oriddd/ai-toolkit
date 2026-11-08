#!/usr/bin/env bash
# Repo hygiene gates that a plain checkout test misses:
#   1. every hook/tool script is executable IN GIT (a fresh clone must not ship 644 hooks); tools/*.py warn only
#   2. no CRLF in shell/python scripts (a Windows autocrlf clone breaks bash shebangs)
#   3. .gitattributes pins LF for scripts
# Usage: bash tools/check-repo-hygiene.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
fail=0
# 1. git modes
while IFS= read -r line; do
  mode="${line%% *}"; path="${line#*$'\t'}"
  if [ "$mode" != "100755" ]; then echo "FAIL: $path is mode $mode in git, must be 100755 (git update-index --chmod=+x)"; fail=1; fi
done < <(git ls-files -s -- 'plugins/*/hooks/*.sh' 'plugins/*/hooks/*.py' 'plugins/*/scripts/*.sh' 'tools/*.sh' 'prepare-for-publish.sh' 2>/dev/null)
# tools/*.py are run as `python3 tools/x.py`, so a missing +x only breaks `./tools/x.py`: warn, don't fail.
while IFS= read -r line; do
  mode="${line%% *}"; path="${line#*$'\t'}"
  if [ "$mode" != "100755" ]; then
    if [ -x "$path" ]; then echo "WARN: $path is executable on disk but mode $mode in git — stage the mode change (git add $path)"
    else echo "WARN: $path is mode $mode in git; make it executable (git update-index --chmod=+x $path)"; fi
  fi
done < <(git ls-files -s -- 'tools/*.py' 2>/dev/null)
# 2. CRLF
while IFS= read -r f; do
  [ -f "$f" ] || continue
  if grep -q $'\r' "$f"; then echo "FAIL: $f contains CRLF line endings"; fail=1; fi
done < <(git ls-files -- '*.sh' '*.py' '*.txt' '*.json' 'plugins/*/hooks/*' 2>/dev/null)
# 3. .gitattributes
if ! grep -Eq '^\*\.sh +text +eol=lf' .gitattributes 2>/dev/null; then echo "FAIL: .gitattributes must pin '*.sh text eol=lf'"; fail=1; fi
[ $fail -eq 0 ] && echo "repo hygiene OK (modes, line endings, .gitattributes)"
exit $fail

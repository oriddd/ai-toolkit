#!/usr/bin/env bash
#
# prepare-for-publish.sh — publication gate for the ai-toolkit repo.
#
# Run this before publishing / opening a release PR. It:
#   1. Fails if any irrelevant/junk files are present (session summaries from
#      other agents, shell captures, .DS_Store, IDE dirs, broken symlinks…).
#   2. Fails if any confidential/internal term or absolute user path leaks
#      into tracked content (usernames, internal codenames, real repo names…).
#   3. Runs every catalogue validator (indexes in sync, skills lint,
#      context templates).
#
# Exit code 0 = safe to publish. Non-zero = fix the reported issues first.
#
# Usage:
#   bash prepare-for-publish.sh
#   ./prepare-for-publish.sh            # after chmod +x
#
# Extend the confidential blocklist without editing this file by creating a
# `.publication-blocklist` at the repo root (one substring per line, `#` = comment).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[1;33m'; BLU='\033[0;34m'; NC='\033[0m'
FAILURES=0

section() { printf "\n${BLU}==> %s${NC}\n" "$1"; }
pass()    { printf "  ${GRN}OK${NC}    %s\n" "$1"; }
fail()    { printf "  ${RED}FAIL${NC}  %s\n" "$1"; FAILURES=$((FAILURES + 1)); }
warn()    { printf "  ${YEL}WARN${NC}  %s\n" "$1"; }

# Only look at files git actually tracks (plus the working tree), never .git internals.
tracked() { git ls-files 2>/dev/null; }

# ---------------------------------------------------------------------------
# 1. Irrelevant / junk files
# ---------------------------------------------------------------------------
section "1. Irrelevant / junk files"

# 1a. Session-summary & scratch docs left behind by AI agents.
JUNK_GLOBS=(
  "*SESSION_SUMMARY.md"
  "*SESSION-SUMMARY.md"
  "*_SUMMARY.md"
  "PATTERN_UPDATES.md"
  "*SCRATCH*.md"
  "*SCRATCHPAD*.md"
  "*.orig"
  "*.rej"
  "*.bak"
  "typescript"
  "typescript-*"
)
junk_found=0
while IFS= read -r f; do
  base="$(basename "$f")"
  for g in "${JUNK_GLOBS[@]}"; do
    # shellcheck disable=SC2053
    if [[ "$base" == $g ]]; then
      fail "junk file tracked: $f"
      junk_found=1
      break
    fi
  done
done < <(tracked)
[ "$junk_found" -eq 0 ] && pass "no session-summary / scratch / backup files tracked"

# 1b. OS / editor noise that must never be committed.
noise=0
while IFS= read -r f; do
  case "$f" in
    *.DS_Store|.idea/*|*.iml|.vscode/*)
      fail "OS/editor file tracked (add to .gitignore): $f"; noise=1 ;;
  esac
done < <(tracked)
[ "$noise" -eq 0 ] && pass "no .DS_Store / .idea / IDE files tracked"

# 1c. Broken or self-referential symlinks anywhere in the tree.
sym=0
while IFS= read -r link; do
  target="$(readlink "$link")"
  # self-referential (points at repo root or its own ancestor) OR dangling
  if [ ! -e "$link" ]; then
    fail "broken symlink: $link -> $target"; sym=1
  elif [ "$(cd "$(dirname "$link")" && cd "$target" 2>/dev/null && pwd)" = "$ROOT" ] 2>/dev/null; then
    fail "self-referential symlink: $link -> $target"; sym=1
  fi
done < <(find . -path ./.git -prune -o -type l -print 2>/dev/null)
[ "$sym" -eq 0 ] && pass "no broken / self-referential symlinks"

# 1d. Ensure a .gitignore exists.
if [ -f "$ROOT/.gitignore" ]; then
  pass ".gitignore present"
else
  fail ".gitignore is missing (OS/editor noise will leak into commits)"
fi

# ---------------------------------------------------------------------------
# 2. Confidential / internal content   (only git-tracked files are published)
# ---------------------------------------------------------------------------
section "2. Confidential / internal content"

# 2a. Absolute user paths (leak usernames + machine directory codenames).
if git grep -nIE "/Users/[a-z0-9._-]+/" -- '*.md' '*.sh' '*.yaml' '*.yml' 2>/dev/null \
      | grep -v "/path/to/" > /tmp/pfp_paths.$$; then
  while IFS= read -r line; do fail "absolute user path leak: $line"; done < /tmp/pfp_paths.$$
else
  pass "no absolute /Users/<name>/ paths in tracked files"
fi
rm -f /tmp/pfp_paths.$$

# 2b. Blocklisted confidential terms (built-in defaults + optional file).
DEFAULT_BLOCK=(oriddd odafna)
BLOCK=("${DEFAULT_BLOCK[@]}")
if [ -f "$ROOT/.publication-blocklist" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(echo "$line" | xargs 2>/dev/null)"
    [ -n "$line" ] && BLOCK+=("$line")
  done < "$ROOT/.publication-blocklist"
  pass "loaded extra terms from .publication-blocklist"
else
  warn "no .publication-blocklist file (using built-in defaults only)"
fi

block_found=0
for term in "${BLOCK[@]}"; do
  if git grep -nI -- "$term" -- . ':(exclude)prepare-for-publish.sh' ':(exclude).publication-blocklist' 2>/dev/null \
        > /tmp/pfp_block.$$; then
    while IFS= read -r line; do fail "blocklisted term '$term': ${line:0:120}"; done < /tmp/pfp_block.$$
    block_found=1
  fi
  rm -f /tmp/pfp_block.$$
done
[ "$block_found" -eq 0 ] && pass "no blocklisted confidential terms in tracked files"

# 2c. Obvious secrets.
if git grep -nIE "(ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]+|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)" \
      -- . ':(exclude)prepare-for-publish.sh' 2>/dev/null > /tmp/pfp_sec.$$; then
  while IFS= read -r line; do fail "possible secret: ${line:0:120}"; done < /tmp/pfp_sec.$$
else
  pass "no obvious secrets (tokens / private keys)"
fi
rm -f /tmp/pfp_sec.$$

# ---------------------------------------------------------------------------
# 3. Catalogue validators
# ---------------------------------------------------------------------------
section "3. Catalogue validators"

run_validator() {
  local label="$1"; shift
  if "$@" > /tmp/pfp_val.$$ 2>&1; then
    pass "$label"
  else
    fail "$label"
    sed 's/^/        /' /tmp/pfp_val.$$
  fi
  rm -f /tmp/pfp_val.$$
}

if [ -d "$ROOT/copilot" ]; then
  run_validator "indexes in sync (build-indexes.py --check)" \
    python3 "$ROOT/copilot/public/skills/build-indexes.py" --check
  run_validator "skills lint (validate-skills.sh)" \
    bash "$ROOT/copilot/public/skills/validate-skills.sh"
  run_validator "context templates (validate-context.sh)" \
    bash "$ROOT/copilot/context/validate-context.sh"
else
  fail "copilot/ directory not found — cannot run catalogue validators"
fi

# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------
printf "\n"
if [ "$FAILURES" -eq 0 ]; then
  printf "${GRN}✔ READY TO PUBLISH — all checks passed.${NC}\n"
  exit 0
else
  printf "${RED}✖ NOT READY — %d check(s) failed. Fix the items above before publishing.${NC}\n" "$FAILURES"
  exit 1
fi



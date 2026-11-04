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

# 1c. Broken symlinks, or symlinks that point at the repo root, anywhere in the tree.
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
if git grep -nIoE "(/Users/[A-Za-z0-9._-]+/|/home/[A-Za-z0-9._-]+/|C:\\\\Users\\\\[A-Za-z0-9._-]+)" -- . ':(exclude)prepare-for-publish.sh' 2>/dev/null \
      | grep -vE ":/(Users|home)/(name|user|username|you|me|example)/$" > /tmp/pfp_paths.$$; then
  while IFS= read -r line; do fail "absolute user path leak: $line"; done < /tmp/pfp_paths.$$
else
  pass "no absolute user paths (/Users, /home, C:\\Users) in tracked files"
fi
rm -f /tmp/pfp_paths.$$

# 2b. Blocklisted confidential terms (built-in defaults + optional file).
# Personal/company terms live ONLY in the gitignored .publication-blocklist, never in this tracked script.
BLOCK=()
if [ -f "$ROOT/.publication-blocklist" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"   # not xargs: it chokes on quotes and would drop the term
    [ -n "$line" ] && BLOCK+=("$line")
  done < "$ROOT/.publication-blocklist"
  pass "loaded extra terms from .publication-blocklist"
else
  fail "no .publication-blocklist file — the confidential-term, identity and history checks cannot run (create it; it is gitignored)"
fi

block_found=0
for term in ${BLOCK[@]+"${BLOCK[@]}"}; do
  if git grep -niI -F -e "$term" -- . ':(exclude).publication-blocklist' 2>/dev/null \
        > /tmp/pfp_block.$$; then
    while IFS= read -r line; do fail "blocklisted term '$term': ${line:0:120}"; done < /tmp/pfp_block.$$
    block_found=1
  fi
  rm -f /tmp/pfp_block.$$
done
[ "$block_found" -eq 0 ] && pass "no blocklisted confidential terms in tracked files"

# 2d. File names, git identity and git HISTORY (pushed history is what the world sees).
name_hits=0
for term in ${BLOCK[@]+"${BLOCK[@]}"}; do
  if git ls-files | grep -iF -- "$term" > /tmp/pfp_names.$$; then
    while IFS= read -r line; do fail "blocklisted term '$term' in file name: $line"; done < /tmp/pfp_names.$$; name_hits=1
  fi
  rm -f /tmp/pfp_names.$$
done
[ "$name_hits" -eq 0 ] && pass "no blocklisted terms in tracked file names"

ident="$(git config user.name) <$(git config user.email)>"
ident_hit=0
for term in ${BLOCK[@]+"${BLOCK[@]}"}; do
  if printf '%s' "$ident" | grep -qiF -- "$term"; then fail "git identity for new commits contains blocklisted term '$term': $ident"; ident_hit=1; fi
done
[ "$ident_hit" -eq 0 ] && pass "git identity for new commits is clean ($ident)"

hist_hit=0
for term in ${BLOCK[@]+"${BLOCK[@]}"}; do
  n_meta="$(git log --all --format='%an %ae %cn %ce%n%B' | grep -ciF -- "$term")"
  n_content="$(git rev-list --all | xargs -I{} git grep -liI -F -e "$term" {} 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${n_meta:-0}" -gt 0 ] || [ "${n_content:-0}" -gt 0 ]; then
    fail "git history contains '$term' (commit metadata lines: $n_meta, file revisions: $n_content) — rewrite history before publishing"; hist_hit=1
  fi
done
[ "$hist_hit" -eq 0 ] && pass "git history (metadata + content, all refs) free of blocklisted terms"

# 2e. Heuristic leak classes the blocklist cannot know about (review, do not ignore).
git grep -nIE "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}" -- . ':(exclude)LICENSE' 2>/dev/null \
  | grep -vE "noreply|example\.(com|org)|@types/|Name <email>|@sentry/|@react|@tanstack|@testing|@expo|@typescript|@mermaid|@babel|@eslint" \
  | while IFS= read -r line; do warn "email-like string: ${line:0:120}"; done
git grep -nIE "\b[A-Z]{2,6}-[0-9]{2,6}\b" -- . 2>/dev/null \
  | grep -vE "PROJ-|TICKET-|ADR-|JSR-|ISO-|RFC-|UTF-|SHA-|CVE-|TD-0|AES-|HS-|HTTP-|TLS-" \
  | while IFS= read -r line; do warn "ticket-key-like string: ${line:0:120}"; done
git grep -nIE "https?://[A-Za-z0-9.-]+\.(local|internal|corp|lan)\b|:8443\b" -- . ':(exclude)prepare-for-publish.sh' 2>/dev/null \
  | while IFS= read -r line; do fail "internal-looking host: ${line:0:120}"; done

# 2f. AI-tool attribution must not appear in tracked content or in any commit message.
ATTR='Co-Authored-By:[[:space:]]*(Claude|Anthropic)|Generated with \[?Claude|noreply@anthropic\.com'
if git grep -nIE "$ATTR" -- . ':(exclude)prepare-for-publish.sh' >/tmp/pfp_attr.$$ 2>/dev/null; then
  while IFS= read -r line; do fail "AI attribution in tracked content: ${line:0:120}"; done < /tmp/pfp_attr.$$
else
  pass "no AI attribution in tracked content"
fi
rm -f /tmp/pfp_attr.$$
if git log --all --format='%H %B' | grep -Eiq "$ATTR"; then fail "AI attribution trailer found in commit messages"; else pass "no AI attribution in commit messages"; fi

# 2g. Unreachable objects survive a history rewrite until the reflog is expired and gc runs.
unreach_hit=0
if [ ${#BLOCK[@]} -gt 0 ]; then
  while IFS= read -r obj; do
    [ -n "$obj" ] || continue
    body="$(git cat-file -p "$obj" 2>/dev/null)"
    for term in ${BLOCK[@]+"${BLOCK[@]}"}; do
      if printf '%s' "$body" | grep -qiF -- "$term"; then
        fail "unreachable git object $obj still contains blocklisted term '$term' — run: git reflog expire --expire=now --all && git gc --prune=now"
        unreach_hit=1; break
      fi
    done
  done < <(git fsck --unreachable --no-reflogs --no-progress 2>/dev/null | awk '$1=="unreachable" && ($2=="blob"||$2=="commit"){print $3}')
fi
[ "$unreach_hit" -eq 0 ] && pass "no blocklisted terms in unreachable git objects"

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

if [ -d "$ROOT/plugins" ]; then
  run_validator "indexes in sync (build-indexes.py --check)" \
    python3 "$ROOT/tools/build-indexes.py" --check
  run_validator "skills lint (validate-skills.sh)" \
    bash "$ROOT/tools/validate-skills.sh"
  run_validator "relative links (check-links.py)" \
    python3 "$ROOT/tools/check-links.py"
  run_validator "hook behaviour (test-hooks.sh)" \
    bash "$ROOT/tools/test-hooks.sh"
  run_validator "git modes and line endings (check-repo-hygiene.sh)" \
    bash "$ROOT/tools/check-repo-hygiene.sh"
  run_validator "context templates (validate-context.sh)" \
    bash "$ROOT/plugins/ai-toolkit-docs/skills/context-maintenance/templates/context/validate-context.sh"
else
  fail "plugins/ directory not found — cannot run catalogue validators"
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



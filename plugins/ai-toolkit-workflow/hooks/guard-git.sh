#!/usr/bin/env bash
# PreToolUse(Bash): require confirmation before commits, pushes, tags and history rewrites.
# Policy: never commit/push until the developer asks (skill: completion-gate).
# Best-effort safety net for Claude's Bash tool — see guard_git.py. Always exits 0.
d="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
input="$(cat)"

# Preferred: the parser (needs python3 >= 3.6; 3.8+ recommended).
if [ -f "$d/guard_git.py" ] && command -v python3 >/dev/null 2>&1 \
   && python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)' >/dev/null 2>&1; then
  out="$(printf '%s' "$input" | python3 "$d/guard_git.py" 2>/dev/null)"
  if [ $? -eq 0 ]; then
    [ -n "$out" ] && printf '%s\n' "$out"
    exit 0
  fi
fi

# Fallback (no usable python3): coarse text match; catches the common direct forms only.
git_re='(^|[^[:alnum:]_.-])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*[[:space:]]+'
if printf '%s' "$input" | grep -Eq "${git_re}(commit|push|tag|rebase|cherry-pick|merge|am|revert)([^[:alnum:]_-]|\$)" \
   || printf '%s' "$input" | grep -Eq "${git_re}reset[[:space:]]+([^\"]*[[:space:]])?--(hard|merge|keep)" \
   || printf '%s' "$input" | grep -Eq '(^|[^[:alnum:]_.-])gh([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]-][^[:space:]]*)?)*[[:space:]]+(pr[[:space:]]+(create|merge)|release[[:space:]]+create)([^[:alnum:]_-]|$)' \
   || printf '%s' "$input" | grep -Eq '(^|[^[:alnum:]_.-])(npm|yarn|pnpm)[[:space:]]+(version|publish)([^[:alnum:]_-]|$)' \
   || printf '%s' "$input" | grep -Eq '(^|[^[:alnum:]_.-])(mvn|mvnw|\./mvnw)[[:space:]]([^;&|]*[[:space:]])?(release:|deploy([^[:alnum:]_-]|$))'; then
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"ai-toolkit policy: do not commit, push, tag, release or rewrite history until the developer asks. Approve only if you asked for it."}}
JSON
fi
exit 0

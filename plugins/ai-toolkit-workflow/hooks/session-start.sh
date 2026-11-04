#!/usr/bin/env bash
# SessionStart: inject the language-neutral routing rules and warn when old user-level copies of
# ai-toolkit skills/agents (~/.claude/skills, ~/.claude/agents) shadow the plugin versions.
# Output goes into the session context, so keep it short. Always exits 0.
d="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -r "$d/routing.md" ] && cat "$d/routing.md"

home="${HOME:-}"
names="$d/shipped-names.txt"
if [ -n "$home" ] && [ -r "$names" ]; then
  n=0; sample=""
  while IFS=: read -r kind name; do
    name="${name%$'\r'}"; kind="${kind%$'\r'}"
    [ -n "$name" ] || continue
    hit=0
    case "$kind" in
      skill) [ -f "$home/.claude/skills/$name/SKILL.md" ] && hit=1 ;;
      agent) [ -f "$home/.claude/agents/$name.md" ] && hit=1 ;;
    esac
    if [ "$hit" -eq 1 ]; then
      n=$((n + 1))
      [ "$n" -le 4 ] && sample="$sample $name"
    fi
  done < "$names"
  if [ "$n" -gt 0 ]; then
    printf '\nai-toolkit WARNING: %s user-level skills/agents in ~/.claude share names with ai-toolkit plugins (e.g.%s) and shadow the plugin versions — ignore if they are your own. Load skills by qualified name (plugin:skill); if they are old copies of this toolkit, tell the developer to run scripts/remove-old-copies.sh from the ai-toolkit-workflow plugin.\n' "$n" "$sample"
  fi
fi
exit 0

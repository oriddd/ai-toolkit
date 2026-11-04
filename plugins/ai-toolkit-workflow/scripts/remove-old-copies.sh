#!/usr/bin/env bash
# Lists — and with --apply moves to a backup folder — old user-level copies of ai-toolkit skills and agents
# in ~/.claude/skills and ~/.claude/agents that would shadow the plugin versions. Never deletes anything.
#   bash remove-old-copies.sh           # dry run: list only
#   bash remove-old-copies.sh --apply   # move to ~/.claude/ai-toolkit-old-copies-backup-<timestamp>/
set -u
d="$(cd "$(dirname "$0")" && pwd)"
names="$d/../hooks/shipped-names.txt"
home="${HOME:?HOME is not set}"
apply=0; [ "${1:-}" = "--apply" ] && apply=1
[ -r "$names" ] || { echo "shipped-names.txt not found next to this plugin"; exit 1; }
stamp="$(date +%Y%m%d-%H%M%S)"; backup="$home/.claude/ai-toolkit-old-copies-backup-$stamp"
found=0
while IFS=: read -r kind name; do
  name="${name%$'\r'}"; kind="${kind%$'\r'}"
  [ -n "$name" ] || continue
  case "$kind" in
    skill) src="$home/.claude/skills/$name"; [ -f "$src/SKILL.md" ] || continue; dest="$backup/skills/$name" ;;
    agent) src="$home/.claude/agents/$name.md"; [ -f "$src" ] || continue; dest="$backup/agents/$name.md" ;;
    *) continue ;;
  esac
  found=$((found + 1))
  if [ "$apply" -eq 1 ]; then
    mkdir -p "$(dirname "$dest")" && mv "$src" "$dest" && echo "moved   $kind $name"
  else
    echo "found   $kind $name  ($src)"
  fi
done < "$names"
if [ "$found" -eq 0 ]; then echo "No old copies found."; exit 0; fi
if [ "$apply" -eq 1 ]; then
  echo; echo "Moved $found item(s) to $backup — restore by moving them back."
else
  echo; echo "$found old copy(ies) found. Review, then re-run with --apply (moves them to a backup folder; nothing is deleted)."
  echo "Only remove copies you did not customise: a skill you edited yourself under the same name would be moved too."
fi

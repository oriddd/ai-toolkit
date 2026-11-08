#!/usr/bin/env bash
# Lists — and with --apply moves to a backup folder — old user-level copies of ai-toolkit skills and agents
# in ~/.claude/skills and ~/.claude/agents that would shadow the plugin versions. Never deletes anything.
#   bash remove-old-copies.sh           # dry run: list only
#   bash remove-old-copies.sh --apply   # move the ones that look like ai-toolkit copies to
#                                       # ~/.claude/ai-toolkit-old-copies-backup-<timestamp>/
#   bash remove-old-copies.sh --apply --all   # also move same-named items that do not look like copies
# "Looks like a copy": a skill whose frontmatter has the toolkit's `tier:`/`applies_to:` keys, or an agent
# with the toolkit's "# Agent:" / "> **Purpose:**" header. Anything else is listed but left alone.
set -u
d="$(cd "$(dirname "$0")" && pwd)"
names="$d/../hooks/shipped-names.txt"
home="${HOME:?HOME is not set}"
apply=0; all=0
for a in "$@"; do case "$a" in --apply) apply=1 ;; --all) all=1 ;; *) echo "unknown option: $a"; exit 2 ;; esac; done
[ -r "$names" ] || { echo "shipped-names.txt not found next to this plugin"; exit 1; }
stamp="$(date +%Y%m%d-%H%M%S)"; backup="$home/.claude/ai-toolkit-old-copies-backup-$stamp"
k=1; while [ -e "$backup" ]; do k=$((k + 1)); backup="$home/.claude/ai-toolkit-old-copies-backup-$stamp-$k"; done
looks_like_copy() { # $1 kind, $2 file
  case "$1" in
    skill) sed -n '1,30p' "$2" 2>/dev/null | grep -Eq '^(tier|applies_to):' ;;
    agent) grep -Eq '^# Agent:|^> \*\*Purpose:\*\*' "$2" 2>/dev/null ;;
  esac
}
found=0; moved=0; kept=0
while IFS=: read -r kind name; do
  name="${name%$'\r'}"; kind="${kind%$'\r'}"
  [ -n "$name" ] || continue
  case "$kind" in
    skill) src="$home/.claude/skills/$name"; [ -f "$src/SKILL.md" ] || continue; dest="$backup/skills/$name" ;;
    agent) src="$home/.claude/agents/$name.md"; [ -f "$src" ] || continue; dest="$backup/agents/$name.md" ;;
    *) continue ;;
  esac
  found=$((found + 1))
  file="$src"; [ "$kind" = skill ] && file="$src/SKILL.md"
  if looks_like_copy "$kind" "$file"; then tag="copy"; else tag="custom?"; fi
  if [ "$apply" -eq 1 ] && [ "$tag" = "custom?" ] && [ "$all" -eq 0 ]; then
    kept=$((kept + 1)); echo "kept    $kind $name  (does not look like an ai-toolkit copy; use --all to move it too)"
  elif [ "$apply" -eq 1 ]; then
    if mkdir -p "$(dirname "$dest")" && mv "$src" "$dest"; then moved=$((moved + 1)); echo "moved   $kind $name"; else echo "FAILED  $kind $name  ($src)" >&2; fi
  else
    echo "found   $kind $name  [$tag]  ($src)"
  fi
done < "$names"
if [ "$found" -eq 0 ]; then echo "No old copies found."; exit 0; fi
if [ "$apply" -eq 1 ]; then
  echo; echo "Moved $moved of $found item(s) to $backup — restore by moving them back."
  [ "$kept" -eq 0 ] || echo "Kept $kept same-named item(s) that do not look like ai-toolkit copies."
else
  echo; echo "$found old copy(ies) found. Review, then re-run with --apply (moves them to a backup folder; nothing is deleted)."
  echo "--apply moves only items marked [copy]; items marked [custom?] are yours unless you know otherwise (--all moves them too)."
fi

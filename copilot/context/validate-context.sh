#!/usr/bin/env bash
# Validates that every .md file in context/ has its (REQUIRED) sections.
set -euo pipefail
CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
errors=0
for f in "$CONTEXT_DIR"/*.md; do
  [ -e "$f" ] || continue
  rel="$(basename "$f")"
  # Search for (REQUIRED) headers that don't have enough content
  # This is a simple check: at least one line of non-comment text after the header.
  while read -r line; do
    if [[ "$line" =~ ^(##+.*\(REQUIRED\)) ]]; then
      header="${BASH_REMATCH[1]}"
      # Check if there is actual content before the next header or end of file
      has_content=0
      found_next=0
      while read -r content_line; do
        if [[ "$content_line" =~ ^##+ ]]; then
           found_next=1
           break
        fi
        # Ignore comments and empty lines
        if [[ ! "$content_line" =~ ^[[:space:]]*$ ]] && [[ ! "$content_line" =~ ^"<!--" ]]; then
          has_content=1
          break
        fi
      done
      if [ "$has_content" -eq 0 ]; then
        echo "ERR: $rel: section '$header' is empty but required."
        errors=$((errors + 1))
      fi
    fi
  done < "$f"
done
if [ "$errors" -gt 0 ]; then
  echo "FAILED: $errors context section(s) missing content."
  exit 1
fi
echo "OK: All context files validated."

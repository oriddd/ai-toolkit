#!/usr/bin/env bash
# Validates that every .md file in context/ has content under each (REQUIRED) section.
# "Content" = at least one line that is not blank and not inside an HTML comment (comments may span lines).
set -euo pipefail
CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
errors=0
for f in "$CONTEXT_DIR"/*.md; do
  [ -e "$f" ] || continue
  rel="$(basename "$f")"
  out="$(awk -v rel="$rel" '
    function flush() {
      if (in_req && !has_content) printf "ERR: %s: section \047%s\047 is empty but required.\n", rel, header
    }
    /^##+/ { flush(); in_req = ($0 ~ /\(REQUIRED\)/); header = $0; has_content = 0; in_comment = 0; next }
    in_req {
      line = $0; text = ""
      while (length(line) > 0) {
        if (in_comment) {
          i = index(line, "-->")
          if (i == 0) { line = ""; break }
          line = substr(line, i + 3); in_comment = 0
        } else {
          i = index(line, "<!--")
          if (i == 0) { text = text line; line = ""; break }
          text = text substr(line, 1, i - 1); line = substr(line, i + 4); in_comment = 1
        }
      }
      if (text !~ /^[ \t\r]*$/) has_content = 1
    }
    END { flush() }
  ' "$f")"
  if [ -n "$out" ]; then
    echo "$out"
    errors=$((errors + $(printf '%s\n' "$out" | wc -l)))
  fi
done
if [ "$errors" -gt 0 ]; then
  echo "FAILED: $errors context section(s) missing content."
  exit 1
fi
echo "OK: All context files validated."

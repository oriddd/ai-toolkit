#!/usr/bin/env bash
# Validates that every .md file in context/ has content under each (REQUIRED) section.
# Sections marked (REQUIRED for services) are required unless project-overview.md has a line
# "Project type: library", "cli" or "mobile" (outside an HTML comment).
# "Content" = at least one line that is not blank, not inside an HTML comment (comments may span lines), not a bare
# code-fence delimiter (an empty ``` block is not content) and not a TODO/TBD placeholder.
set -euo pipefail
CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
errors=0
project_type="$(sed -n 's/^[[:space:]]*[-*]*[[:space:]]*\**Project type:\**[[:space:]]*\([A-Za-z-]*\).*/\1/p' "$CONTEXT_DIR/project-overview.md" 2>/dev/null | head -n 1 | tr '[:upper:]' '[:lower:]' || true)"
case "$project_type" in
  library|cli|mobile) service=0 ;;
  *) service=1 ;;
esac
for f in "$CONTEXT_DIR"/*.md; do
  [ -e "$f" ] || continue
  rel="$(basename "$f")"
  out="$(awk -v rel="$rel" -v service="$service" '
    function flush() {
      if (in_req && !has_content) printf "ERR: %s: section \047%s\047 is empty but required.\n", rel, header
    }
    !in_comment && /^[ \t]*(```|~~~)/ { in_fence = !in_fence; next }
    !in_fence && !in_comment && /^##+/ { flush(); in_req = ($0 ~ /\(REQUIRED\)/) || (service && $0 ~ /\(REQUIRED for services\)/); header = $0; has_content = 0; next }
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
      if (text !~ /^[ \t\r]*$/ && text !~ /^[ \t\r]*[-*]?[ \t]*(TODO|TBD)[ \t\r.:]*$/) has_content = 1
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

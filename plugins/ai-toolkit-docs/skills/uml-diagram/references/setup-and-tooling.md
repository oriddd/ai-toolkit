# UML Diagram — Mermaid setup, validation and troubleshooting

Loaded from [`uml-diagram`](../SKILL.md).


### Where Mermaid renders

Mermaid renders automatically on:
- **GitHub** - Native support in markdown files
- **GitLab** - Native support in markdown files
- **Azure DevOps** - Native support
- **Notion** - Supports Mermaid blocks
- **Confluence** - Via Mermaid plugin
- **VS Code** - Via extensions
- **IntelliJ IDEA** - Via plugins

### IDE Integration

**VS Code**:
1. Install "Markdown Preview Mermaid Support" extension
2. Or install "Mermaid Editor" for dedicated view
3. Open any `.md` file with Mermaid diagram
4. Press `Ctrl+Shift+V` (Cmd+Shift+V on Mac) to preview

**IntelliJ IDEA**:
1. Install "Mermaid" plugin from marketplace
2. Open `.md` file → preview shows automatically
3. Or use built-in markdown preview (supports Mermaid natively in newer versions)

**Eclipse**:
1. Install "Markdown Editor" with Mermaid support
2. Open `.md` file → preview renders Mermaid

### Online Editors

- **Mermaid Live Editor**: https://mermaid.live/
- **Draw.io**: Supports Mermaid import
- **GitHub**: Edit directly in web interface and preview

### CLI Tool (Optional)

If you need to generate static images:

```bash
# Install globally
npm install -g @mermaid-js/mermaid-cli@<pinned-version>   # developer-run / CI, pinned — an agent does not install tools

# From a .md input, mmdc writes one image per mermaid block (diagram-1.png, diagram-2.png, …)
# Generate PNG
mmdc -i diagram.md -o diagram.png

# Generate SVG
mmdc -i diagram.md -o diagram.svg

# Generate PDF
mmdc -i diagram.md -o diagram.pdf
```

But usually **not needed** - just commit the `.md` files!

## Validation

### Syntax Check

The best way to validate is:
1. **IDE Preview**: Most markdown plugins show errors if syntax is invalid.
2. **Mermaid Live Editor**: Paste your code into https://mermaid.live/ to verify.
3. **CLI**: Use `mmdc` to verify it compiles to image if needed.

### CI/CD Integration

You can use the Mermaid CLI in your pipeline to validate syntax:

**GitHub Actions**:
```yaml
- name: Validate Mermaid Syntax
  run: |
    # CI step, pinned — an agent does not install tools. mmdc rejects -o /dev/null, so render into a temp dir;
    # headless Chromium in a container needs --no-sandbox.
    tmp="$(mktemp -d)"; echo '{"args":["--no-sandbox"]}' > "$tmp/puppeteer.json"
    for f in context/*.md; do
      grep -q '^```mermaid' "$f" || continue
      npx -y @mermaid-js/mermaid-cli@<pinned-version> -p "$tmp/puppeteer.json" \
        -i "$f" -o "$tmp/$(basename "$f" .md).svg" || exit 1
    done
```

## Troubleshooting

### Common Issues

**Issue**: Diagram doesn't render on GitHub
**Solution**: Ensure you used the ` ```mermaid ` identifier and closed it with ` ``` `. Also ensure it's in a `.md` file.

**Issue**: "Maximum text size in diagram exceeded" or "Edge limit exceeded"
**Solution**: The diagram is over Mermaid's `maxTextSize` (50,000 characters) or, for flowcharts, `maxEdges` (500) limit (defaults in Mermaid 11). Split it into
smaller diagrams (one concept each, see Best Practices) rather than raising the limits.

**Issue**: Sequence diagram arrows looking weird
**Solution**: Check the arrow syntax (`->>` for solid, `-->>` for dashed). Avoid mixing them if not intended.

## Resources

- **Mermaid Official**: https://mermaid.js.org/
- **Mermaid Live Editor**: https://mermaid.live/
- **C4 with Mermaid**: https://mermaid.js.org/syntax/c4.html
- **Mermaid Cheat Sheet**: https://mermaid.js.org/syntax/flowchart.html

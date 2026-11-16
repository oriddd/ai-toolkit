# Context Maintenance — generating and viewing diagrams

Loaded from [`context-maintenance`](../SKILL.md).

## Generating Diagrams

Most platforms (GitHub, GitLab) render Mermaid natively from markdown files. No generation step is required!

If you need a static image for a document that doesn't support Mermaid:

```bash
# Install Mermaid CLI
npm install -g @mermaid-js/mermaid-cli@<pinned-version>   # developer-run / CI, pinned — an agent does not install tools

# Generate PNG from markdown file containing mermaid block (one image per block: system-context-1.png, …)
mmdc -i context/system-context.md -o system-context.png
```

## Viewing Diagrams

- **GitHub/GitLab**: View the `.md` file directly in the web interface.
- **VS Code**: Use "Markdown Preview Mermaid Support" extension.
- **IntelliJ IDEA**: Use "Mermaid" plugin.
- **Online**: Use the [Mermaid Live Editor](https://mermaid.live/).


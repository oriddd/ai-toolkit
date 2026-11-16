# Context Maintenance — validation and automation

Loaded from [`context-maintenance`](../SKILL.md).

## Validation

### Context Documentation Health Check

```bash
# Check for broken links (requires markdown-link-check)
npx markdown-link-check@<pinned-version> context/*.md

# Validate Mermaid syntax (mermaid-cli via npx; mmdc rejects -o /dev/null, so render into a temp dir)
tmp="$(mktemp -d)"; echo '{"args":["--no-sandbox"]}' > "$tmp/puppeteer.json"   # --no-sandbox: headless Chromium in containers
for f in context/*.md; do
  grep -q '^```mermaid' "$f" || continue
  npx -y @mermaid-js/mermaid-cli@<pinned-version> -p "$tmp/puppeteer.json" -i "$f" -o "$tmp/$(basename "$f" .md).svg" || exit 1
done

# Required sections filled in
bash context/validate-context.sh

# Check for outdated dates (manual review)
grep -r "Last Updated" context/
```

### Quality Criteria

Good context documentation:
- Less than 3 months old
- No broken links
- Code examples compile
- Mermaid diagrams render correctly
- Metrics are current
- Cross-references valid
- No TODO markers


## Automation Opportunities

### Git Hooks

Add a reminder hook to the repo's `.pre-commit-config.yaml` (a hand-written `.git/hooks/pre-commit` is overwritten by
`pre-commit install`), with the script versioned in the repo:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: context-docs-reminder
        name: remind to update context/
        entry: scripts/context-reminder.sh
        language: script
        pass_filenames: false
        always_run: true
        verbose: true        # print the reminder even though the hook passes
```

```bash
#!/bin/bash
# scripts/context-reminder.sh (chmod +x) — never fails the commit, only reminds

if git diff --cached --name-only | grep -qE "^(src|app|lib)/"; then
    echo "Remember to update context/ documentation if needed!"
    echo "   - architecture.md for new components"
    echo "   - code-standards.md for new patterns"
    echo "   - progress-tracker.md for milestones"
fi
```

### CI Pipeline Check

Add to the CI pipeline (Jenkinsfile shown; the same step works in GitHub Actions):

```groovy
stage('Documentation Check') {
    steps {
        sh 'npx markdown-link-check@<pinned-version> context/*.md'
        sh 'bash context/validate-context.sh'
        // Validate mermaid diagrams — CI only, pinned; an agent does not install tools
        sh '''
          tmp="$(mktemp -d)"; echo '{"args":["--no-sandbox"]}' > "$tmp/puppeteer.json"   # --no-sandbox: headless Chromium in containers
          for f in context/*.md; do
            grep -q '^```mermaid' "$f" || continue
            npx -y @mermaid-js/mermaid-cli@<pinned-version> -p "$tmp/puppeteer.json" -i "$f" -o "$tmp/$(basename "$f" .md).svg" || exit 1
          done
        '''
    }
}
```


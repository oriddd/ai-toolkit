# Claude Code Setup

Claude Code applies a skill only when it loads it. The marketplace therefore ships routing hooks that tell the model which
skills to load before it writes code, and a definition of done (`completion-gate`) that it must prove before saying a task is
finished.

## Install

```
/plugin marketplace add oriddd/ai-toolkit
/plugin install ai-toolkit-java@ai-toolkit             # or ai-toolkit-python / ai-toolkit-react-native
/plugin install ai-toolkit-java-agents@ai-toolkit      # optional: task agents for that language
/reload-plugins
```

Installing a language's plugin pulls in everything that language needs through plugin dependencies. You do not
install the phase plugins one by one.

| You install | You also get (dependencies) |
| --- | --- |
| `ai-toolkit-java` | `-java-design`, `-java-build`, `-java-quality`, `-java-ops`, `ai-toolkit-docs`, `ai-toolkit-workflow`, `ai-toolkit-quality` |
| `ai-toolkit-python` | `-python-design`, `-python-build`, `-python-quality`, `-python-ops`, `ai-toolkit-workflow`, `ai-toolkit-quality` |
| `ai-toolkit-react-native` | `-react-native-design`, `-react-native-build`, `-react-native-quality`, `-react-native-ops`, `ai-toolkit-workflow`, `ai-toolkit-quality` |
| `ai-toolkit-<lang>-agents` | that language's design, build, quality and ops plugins, `ai-toolkit-docs`; the Java agents also `ai-toolkit-java-scaffold` |
| `ai-toolkit-java-scaffold` | `-java-design`, `-java-ops`, `ai-toolkit-docs` |
| `ai-toolkit-docs` | `ai-toolkit-workflow` (and so `ai-toolkit-quality`) |
| `ai-toolkit-workflow` | `ai-toolkit-quality` |
| `ai-toolkit-quality` | — |

A language's routing table is injected only when the project is that language (`pom.xml` / `build.gradle(.kts)` / `settings.gradle(.kts)`,
`pyproject.toml` / `requirements*.txt` / `setup.py` / `setup.cfg` / `Pipfile`, or a `package.json` that contains `react-native`).
Detection looks at the project root only.

## Phase plugins on their own

Each phase plugin declares the plugins its skills depend on, so `ai-toolkit-java-build` alone also installs
`-java-design`, `-java-ops`, `-java-quality` and `ai-toolkit-workflow`. The order is design → quality → ops → build; `-design` depends only on the
neutral `ai-toolkit-quality` (its routing table cites `completion-gate`). `validate-skills.sh` fails a skill dependency its plugin does not declare, and any dependency cycle.

## For a whole team

Register the marketplace once in the repository so everyone is prompted to install it:

```
claude plugin marketplace add oriddd/ai-toolkit --scope project     # writes .claude/settings.json — commit it
claude plugin install ai-toolkit-java@ai-toolkit --scope project
```

The settings keys behind this are `extraKnownMarketplaces` and `enabledPlugins`. Each contributor still runs the
install command once (or accepts the trust prompt) — plugins from an external source are not installed from settings alone.

## Update and remove

```
claude plugin marketplace update ai-toolkit          # refresh the catalogue
claude plugin update ai-toolkit-java-design@ai-toolkit
claude plugin uninstall ai-toolkit-java-design@ai-toolkit
```

In a session use `/plugin` (Marketplaces / Installed tabs), then `/reload-plugins`. Auto-update is off by default for
third-party marketplaces; enable it per marketplace in `/plugin`.

Plugins are cached by their `version`. A change that does not bump `version` in the plugin's `plugin.json` is **not**
delivered to installed users — CI (`tools/check-versions.sh`) enforces the bump.

## Old copies in `~/.claude` (important)

If you previously copied these skills or agents into `~/.claude/skills` or `~/.claude/agents` (for example by copying them by hand), those copies are **not** updated by the marketplace and they win name lookups:
user-level agents outrank plugin agents, and a bare `Skill("code-structure")` can load the stale copy instead of
`ai-toolkit-java-design:code-structure`. They also double the context cost.

`ai-toolkit-workflow` warns at session start when it finds such copies. To clean them up safely (dry run first; with
`--apply` they are moved to a timestamped backup folder, nothing is deleted):

```
S="$(ls -d ~/.claude/plugins/cache/ai-toolkit/ai-toolkit-workflow/*/ | sort -V | tail -1)scripts/remove-old-copies.sh"
bash "$S"            # list
bash "$S" --apply    # move to ~/.claude/ai-toolkit-old-copies-backup-<timestamp>/
```

Only move copies you did not customise.

## Context budget

Every installed skill and agent adds its description to the session's skill listing, which Claude Code caps at about 1 %
of the context window. With everything installed that is roughly 9–10k tokens, so **install only the languages you use**
(about 2.5–6k tokens per language plus the neutral plugins). If descriptions are cut short in your setup, raise
`skillListingBudgetFraction` in your settings or install fewer plugins.

Skill *bodies* are not part of this budget: a body loads only when the skill is invoked, and the largest skills keep their
code-heavy sections in `references/` files that load only when that part of the work needs them.

## Windows

The hooks are bash scripts. Use Git for Windows (Git Bash) or WSL, keep `python3` (3.8 or newer) on `PATH` — not the
Microsoft Store alias — and let the repo's `.gitattributes` keep LF line endings (`git config core.autocrlf input` if you
cloned with CRLF). Without bash the hooks fail non-blocking and the commit guard is silently off. Verify with
`bash tools/test-hooks.sh` from a clone of this repository.

## What the commit guard does and does not do

`ai-toolkit-workflow` registers a `PreToolUse` hook that asks for confirmation before direct `git commit|push|tag|rebase|
merge|cherry-pick|am|revert`, `git reset --hard`, `gh pr create|merge`, `gh release create`, `npm version|publish` and
`mvn release:*|deploy` in Claude's Bash tool (multi-line commands, quoted paths, `bash -c`, wrappers like `sudo`/`env` are
parsed). It is a **best-effort safety net, not a security boundary**: it cannot see aliases or variables, scripts that commit
internally, other tools, or anything outside Claude's Bash tool, and it needs `python3` 3.6+ (3.8+ recommended) — otherwise a
coarser text match applies. The real controls are branch protection, server-side rules and a pre-push/commit-msg git hook.
It never blocks: a failure in the hook exits 0.

## Tuning the routing

Each language's routing table is `plugins/ai-toolkit-<lang>-design/hooks/routing.md` (neutral rules:
`plugins/ai-toolkit-workflow/hooks/routing.md`); keep each under ~400 words, they are injected every session. If a skill is
still skipped, tighten its `description:` with a `Use when …` trigger (enforced by `tools/validate-skills.sh`).

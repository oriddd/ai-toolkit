## ai-toolkit workflow (MANDATORY, any language)

Skills apply only if LOADED (Skill tool, qualified name — bare names can resolve to stale copies). Do not work from memory;
load the task's skills before asking clarifying questions.

| Situation | Load first |
| --- | --- |
| Finishing any implementation task (before saying it is done) | `ai-toolkit-quality:completion-gate`, `ai-toolkit-quality:code-hygiene` |
| Sonar / quality gate | `ai-toolkit-quality:sonar-quality-gate` |
| Creating a commit or splitting work into commits | `ai-toolkit-workflow:git-commit-conventions` |
| Writing or updating a PR description | `ai-toolkit-workflow:pr-description` |
| Releases, changelog, versioning | `ai-toolkit-workflow:release-versioning` |
| Work spanning 2+ independent units (layers, tests, docs, review) | `ai-toolkit-workflow:parallel-delegation` |

**Never commit, push or tag until the developer asks.** A best-effort hook asks for confirmation on direct git commands;
it is not a guarantee. When a task is finished run `completion-gate`, report evidence per check, then offer to commit.
Delegate independent units to subagents per `parallel-delegation` and verify what comes back. Subagents cannot ask the
developer: ask HITL questions here, put the answers in the brief, and answer an agent's `NEEDS INPUT:` the same way.
When an agent did the work, relay its completion-gate table verbatim; re-run the gate only if you changed code after it. Postman skills apply only
to Postman collections or workspaces — code standards come from the language routing table.

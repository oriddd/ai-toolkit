## ai-toolkit Python / FastAPI standards (MANDATORY routing)

Standards only apply if the skill is LOADED first. Do not write code from memory. Load with the Skill tool using the
qualified name `ai-toolkit-python-<phase>:<skill>`, phase d=design, b=build, q=quality, o=ops (bare names can resolve to
stale copies).

**Before writing or editing Python — and before asking clarifying questions — load the skills for the task:**

| Task | Load first |
| --- | --- |
| New module / package / service / settings | `python-code-structure` (d) |
| New or changed endpoint, router, dependency | `python-fastapi-conventions` (d), `python-error-handling` (b), `python-input-validation` (b) |
| Outbound HTTP client, settings, dependency injection | `python-code-structure` (d), `python-error-handling` (b) |
| Raising / mapping errors | `python-error-handling` (b) |
| Validation rule | `python-input-validation` (b) |
| Database model / repository / migration | `python-persistence` (b) |
| New or changed test | `python-unit-tests` (q) (+ `python-integration-tests` (q) for real DB/broker) |
| Lint / typing / pre-commit | `python-static-analysis` (q) |
| Pipeline / Dockerfile | `python-ci` (o) |
| Logs / traces / metrics | `python-observability` (o) |

**Python gates**
1. Prefer the smallest pattern that fits; do not over-engineer.
2. Before saying the work is done, run the `ai-toolkit-quality:completion-gate` skill. For Python the verify sequence is defined in `python-static-analysis` (q) §5 (ruff check, ruff format --check, mypy, lint-imports, pytest `-m "not integration"`; plus `-m integration` when Docker is available; exit code 5 = none collected = pass). A failure means the standard was not applied; fix the cause, never weaken a check.
3. Never commit unless the developer asks; before commit / PR, check the diff against the loaded skills' Do/Don't lists.

Postman skills apply only to Postman collections or workspaces — code standards come from this table.

`CLAUDE.md` overrides skill defaults.

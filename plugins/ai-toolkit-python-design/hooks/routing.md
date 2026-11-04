## ai-toolkit Python / FastAPI standards (MANDATORY routing)

Standards only apply if the skill is LOADED first. Do not write code from memory.

**Before writing or editing Python, load the skills for the task:**

| Task | Load first |
| --- | --- |
| New module / package / service / settings | `python-code-structure` |
| New or changed endpoint, router, dependency | `python-fastapi-conventions`, `python-error-handling`, `python-input-validation` |
| Raising / mapping errors | `python-error-handling` |
| Validation rule | `python-input-validation` |
| Database model / repository / migration | `python-persistence` |
| New or changed test | `python-unit-tests` (+ `python-integration-tests` for real DB/broker) |
| Lint / typing / pre-commit | `python-static-analysis` |
| Pipeline / Dockerfile | `python-ci` |
| Logs / traces / metrics | `python-observability` |

**Python gates**
1. Prefer the smallest pattern that fits; do not over-engineer.
2. Before saying the work is done, run the `ai-toolkit-quality:completion-gate` skill. For Python the verify sequence is defined in `python-ci` (ruff check, ruff format --check, mypy, lint-imports, pytest `-m "not integration"`; plus `-m integration` when Docker is available). A failure means the standard was not applied; fix the cause, never weaken a check.
3. Never commit unless the developer asks; before commit / PR, check the diff against the loaded skills' Do/Don't lists.

Postman skills apply only to Postman collections or workspaces — code standards come from this table.

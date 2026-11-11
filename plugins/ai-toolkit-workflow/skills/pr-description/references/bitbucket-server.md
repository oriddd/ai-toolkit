# Bitbucket Server / Data Center — updating a PR description

Loaded from `pr-description` §2 when `git remote get-url origin` points at a self-hosted Bitbucket
(`/scm/<project>/<repo>.git` or `/projects/<PROJ>/repos/<repo>`). This REST API needs care: optimistic locking and a
full PUT body. Ask the developer first, exactly as §2 says.

Keep the token out of the process list: the helper below feeds the header to curl on stdin.

```bash
# Reads the token from the environment; never put it on a command line
bb() { printf 'header = "Authorization: Bearer %s"\n' "$BITBUCKET_TOKEN" | curl -s -K - "$@"; }
```

### Step 1 — Fetch the current PR (captures `version` for optimistic locking, and the reviewers)

```bash
bb "https://<host>/rest/api/1.0/projects/{proj}/repos/{repo}/pull-requests/{id}" > pr.json
jq '{id, title, description, version, reviewers: [.reviewers[] | {user: {name: .user.name}}]}' pr.json
```

Note the `version` integer — it is required for the update call. Keep the `reviewers` list: on some server versions a
PUT without it replaces the reviewers with an empty list.

### Step 2 — Replace the description

Write the new description to a file and let `jq` build the JSON — hand-escaping quotes and newlines breaks on real text:

```bash
body="$(mktemp)"
jq --rawfile description description.md \
   '{version, title, description: $description, reviewers: [.reviewers[] | {user: {name: .user.name}}]}' \
   pr.json > "$body"   # version, title and reviewers come unchanged from Step 1
bb -X PUT \
  -H "Content-Type: application/json" \
  --data @"$body" \
  "https://<host>/rest/api/1.0/projects/{proj}/repos/{repo}/pull-requests/{id}"
rm -f "$body" pr.json
```

**Important:**
- `version` must match the current version or the server returns `409 Conflict`
- `title` must always be included in the PUT body (it resets to empty if omitted)
- `reviewers` must be sent unchanged (some versions drop reviewers that are missing from the body)
- The description must be a valid JSON string — let `jq --rawfile` (Step 2) escape newlines and quotes; never hand-escape
- On `409`, re-fetch the PR to get the latest `version` and retry

### Parsing a PR URL

Given `https://<host>/projects/PROJ/repos/my-service/pull-requests/42`:

| Segment   | Value       | Position in URL              |
|-----------|-------------|------------------------------|
| `project` | `PROJ`      | `/projects/{project}/`       |
| `repo`    | `my-service`| `/repos/{repo}/`             |
| `PR_ID`   | `42`        | `/pull-requests/{PR_ID}`     |

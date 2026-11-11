#!/usr/bin/env bash
# Behavioural tests for the plugin hooks. Exit non-zero on the first failing group.
#   bash tools/test-hooks.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$ROOT/plugins/ai-toolkit-workflow/hooks/guard-git.sh"
fail=0
mk_json() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"; }
expect_ask()   { out="$(mk_json "$1" | "$GUARD")"; if printf '%s' "$out" | grep -q '"permissionDecision": "ask"'; then :; else echo "FAIL (should ask): $1"; fail=1; fi; }
expect_quiet() { out="$(mk_json "$1" | "$GUARD")"; if [ -n "$out" ]; then echo "FAIL (should be quiet): $1"; fail=1; fi; }

ASK=(
  'git commit -m x' 'git commit --amend --no-edit' 'git add -A && git commit -m x' 'git -C /repo commit -m x'
  'git -C "my dir" commit -m x' "git -C '/tmp/my dir' push" 'git push' 'git push origin main' 'git push --force'
  'git push;echo done' 'git commit&&echo ok' 'git commit|cat' 'git commit>/dev/null' '(git push)'
  "bash -c 'git push'" "sh -c 'git commit -m x'" 'bash -c "cd x && git commit -m y"' 'eval "git push"'
  'git "commit" -m x' "git 'commit' -m x" 'GIT_AUTHOR_NAME=x git commit -m y' '/usr/bin/git commit -m x' 'sudo git push'
  'git tag v1.0.0' 'git tag -d v1' 'git rebase -i HEAD~3' 'git cherry-pick abc' 'git merge feature'
  'git revert HEAD' 'git am patch.mbox' 'git reset --hard HEAD~1' 'git -c user.name=x commit -m y' 'git --no-pager commit -m x'
  'gh pr create --fill' 'gh pr merge 12' 'cd /x && git push'
  'git commit -n -m x' 'git merge -n feature' 'git rebase -n main'
  $'cd /x\ngit push' $'echo hi\ngit commit -m x' $'git add .\ngit commit -m "msg"' $'git add . \\\n && git commit -m x'
  '{ git commit -m x; }' 'if true; then git commit -m x; fi' 'for f in a; do git push; done' '! git commit -m x'
  'echo `git commit -m x`' 'sudo -u bob git commit -m x' 'env -i git commit -m x' 'nice -n 5 git push' 'timeout 5 git push' 'xargs -n1 git push'
  'bash -lc "git commit -m x"' 'sh -ec "git push"' 'bash --login -c "git commit -m x"' 'eval git commit -m x' 'bash -c "bash -c \"git push\""'
  'gh -R a/b pr create' 'gh release create v1' 'gh api -X POST repos/a/b/pulls' 'git.exe commit -m x' 'C:\\Program\ Files\\Git\\git.exe push'
  'gh api --method=POST repos/a/b/pulls' 'gh api -XPOST repos/a/b/pulls' 'gh api -X delete repos/a/b' 'gh api --method PATCH repos/a/b/issues/1'
  'gh api repos/a/b/pulls -f title=x' 'gh api repos/a/b/pulls -F draft=true' 'gh api repos/a/b/pulls --field title=x' 'gh api repos/a/b/pulls --input body.json'
  'npm version patch' 'npm publish' 'mvn release:prepare' 'mvn -B release:perform' 'mvn deploy'
  # safe flags count only as real, standalone flags — never as option values or extra arguments (H-1)
  'git commit -m "--abort"' 'git commit -m --dry-run' 'git push origin main --abort' 'git merge origin/main -h' 'git commit -m x -- --dry-run'
  # plumbing and history rewrites (H-2), stash (AG-8)
  'git reset --soft HEAD~1' 'git reset HEAD~1' 'git commit-tree abc -m x' 'git update-ref refs/heads/main abc' 'git branch -f main abc'
  'git checkout -B main' 'git switch -C main' 'git filter-branch --all' 'git filter-repo --path x' 'git pull --rebase' 'git pull -r origin main'
  'git subtree push --prefix x origin main' 'git submodule foreach git push' 'git submodule foreach --recursive "git push"' 'git svn dcommit'
  'git send-email x.patch' 'git stash' 'git stash push -m wip' 'git stash pop' 'git stash drop' 'git stash apply' 'git stash clear'
  # gh writes (H-3) and publishers (H-4)
  'gh pr review 1 --approve' 'gh pr ready 1' 'gh pr close 1' 'gh release upload v1 a.zip' 'gh release edit v1' 'gh repo delete a/b --yes' 'gh workflow run ci.yml'
  'npm --prefix x publish' 'pnpm -r publish' 'yarn npm publish' 'mvnw.cmd deploy' './mvnw deploy' 'gradle publish' './gradlew :lib:publishToSonatype'
  'twine upload dist/x.whl' 'poetry publish' 'cargo publish'
  # evasions (H-5)
  'bash -c -e "git push"' 'echo "git push" | sh' $'bash <<EOF\ngit push\nEOF' 'watch -n 5 "git push"' '$(echo git) push' '`which git` commit -m x' '$GIT push'
  'git -c alias.ci=commit ci -m x' 'git -c alias.p="!git push" p' $'x=$((1<<2))\ngit push' $'ls # note\ngit push'
  # word splitting via $IFS, forced branch delete, full deploy-plugin coordinates, graphql mutations
  'git commit$IFS-m x' 'git commit${IFS}-m x' 'git branch -D x' 'mvn org.apache.maven.plugins:maven-deploy-plugin:deploy'
  'mvn org.apache.maven.plugins:maven-deploy-plugin:3.1.2:deploy-file' 'mvn deploy:deploy-file -Dfile=x' 'mvn -pl app clean deploy'
  'gh api graphql -f query="mutation { addStar(input: {starrableId: \"x\"}) { clientMutationId } }"' 'gh api graphql -F query=@q.graphql'
  'git reset HEAD~1 --' 'yarn version patch'
  # discarding uncommitted work (completion-gate §1)
  'git clean -fdx' 'git clean -f' 'git restore .' 'git restore src/A.java' 'git restore --staged --worktree f' 'git checkout -- f'
  'git checkout .' 'git checkout HEAD f' 'git checkout -f main' 'git switch --discard-changes main'
)
# cases the no-python fallback is not expected to catch (it does not handle substitutions, aliases or heredocs)
FB_SKIP_ASK=('$(echo git) push' '`which git` commit -m x' 'git -c alias.ci=commit ci -m x' 'git -c alias.p="!git push" p')
QUIET=(
  'git status' 'git diff' 'git diff --stat' 'git diff commit' 'git log --oneline' 'git log --grep "git commit"' 'git show HEAD'
  'git branch' 'git branch -a' 'git checkout -b x' 'git switch main' 'git add -A' 'git fetch' 'git pull' 'git remote -v'
  'git stash list' 'git tag' 'git tag -l' 'git tag --list "v*"' 'git reset HEAD file' 'git reset'
  'echo "use git commit later"' 'echo git commit' 'cat commit.txt' 'grep -r "git push" docs' 'mvn -B verify' 'npm run verify'
  'gh pr view 12' 'gh pr list' 'ls -la' 'python3 -m pytest'
  'git merge --abort' 'git rebase --abort' 'git rebase --continue' 'git cherry-pick --abort' 'git push --dry-run' 'git push -n' 'git commit --dry-run'
  'git merge --no-commit feature' 'git commit -h' 'gh pr create --help' 'git rebase --show-current-patch' 'git am --abort'
  $'git status\ngit diff' 'git diff | grep commit' 'git status # commit later' 'git commit-graph verify' 'git merge-base a b'
  'npm run build' 'npm test' 'mvn -B verify' 'mvn dependency:tree' 'gh api repos/a/b/pulls' 'gh api -X GET repos/a/b'
  'gh api --method=GET repos/a/b/pulls -f per_page=1' 'gh api repos/a/b/pulls --jq .[].number' 'gh api -H "Accept: application/json" repos/a/b'
  'git push --dry-run origin main' 'git commit --dry-run -m x' 'git stash list' 'git stash show -p' 'git branch -d x' 'git switch -c y'
  'gh pr checks' 'gh release list' 'gh release view v1' 'gh repo view' 'gh workflow list' 'gh pr review --help' 'npm run release'
  'gradle build' './gradlew publishToMavenLocal' 'echo hi # git push' 'git log --grep "#1 commit"' 'echo "$(git log -1) commit msg"'
  '$EDITOR commit.txt' 'git status | bash' 'git subtree split --prefix x' 'git submodule foreach git status'
  # heredoc bodies are data unless fed to a shell (H-6)
  $'cat <<EOF\ngit commit -m x\nEOF' $'cat > f <<\'EOF\'\ngit push\nEOF\necho ok'
  # option values and read-only forms that mention deploy/publish/version
  'mvn -pl deployment-service verify' 'mvn -f deploy/pom.xml verify' 'mvn -P release verify' 'gradle build -x publish'
  'yarn version --help' 'npm publish --help' "gh api graphql -f query='{ viewer { login } }'" 'git reset HEAD~1 -- file.txt'
  'git reset HEAD~1 a.txt b.txt' 'git clean -n' 'git clean -fdn' 'git clean --dry-run' 'git restore --staged f' 'git checkout main'
  'git checkout -b x origin/x' 'git switch main'
)
FB_SKIP_QUIET=($'cat <<EOF\ngit commit -m x\nEOF' $'cat > f <<\'EOF\'\ngit push\nEOF\necho ok')
for c in "${ASK[@]}";   do expect_ask "$c";   done
for c in "${QUIET[@]}"; do expect_quiet "$c"; done
# git aliases from the user's config are expanded
GCFG="$(mktemp)"; printf '[alias]\n\tci = commit -v\n\tst = status\n\tpub = "!git push origin HEAD"\n' > "$GCFG"
for c in 'git ci -m x' 'git pub'; do out="$(mk_json "$c" | GIT_CONFIG_GLOBAL="$GCFG" "$GUARD")"; printf '%s' "$out" | grep -q '"permissionDecision": "ask"' || { echo "FAIL (alias should ask): $c"; fail=1; }; done
out="$(mk_json 'git st' | GIT_CONFIG_GLOBAL="$GCFG" "$GUARD")"; [ -z "$out" ] || { echo "FAIL (alias should be quiet): git st"; fail=1; }
rm -f "$GCFG"
# nested wrappers must not blow up the runtime
start=$(date +%s); mk_json "$(printf 'nice %.0s' $(seq 40))ls" | "$GUARD" >/dev/null; [ $(( $(date +%s) - start )) -le 3 ] || { echo "FAIL: nested wrappers took too long"; fail=1; }
# a clean command whose description mentions git commit must not fire
out="$(python3 -c 'import json; print(json.dumps({"tool_input":{"command":"ls","description":"git commit later"}}))' | "$GUARD")"
[ -z "$out" ] || { echo "FAIL: description text triggered the guard"; fail=1; }
# fallback path (no python3) must still catch the common cases
SAFEBIN="$(mktemp -d)"; for b in cat dirname grep bash sh env; do ln -s "$(command -v $b)" "$SAFEBIN/$b" 2>/dev/null; done
in_skip() { local x="$1"; shift; local y; for y in "$@"; do [ "$x" = "$y" ] && return 0; done; return 1; }
for c in "${ASK[@]}" 'pnpm version patch'; do
  in_skip "$c" "${FB_SKIP_ASK[@]}" && continue
  out="$(mk_json "$c" | PATH="$SAFEBIN" "$GUARD")"
  printf '%s' "$out" | grep -q '"permissionDecision":"ask"' || { echo "FAIL: no-python fallback missed: $c"; fail=1; }
done
for c in "${QUIET[@]}"; do
  in_skip "$c" "${FB_SKIP_QUIET[@]}" && continue
  out="$(mk_json "$c" | PATH="$SAFEBIN" "$GUARD")"
  [ -z "$out" ] || { echo "FAIL: no-python fallback fired on: $c"; fail=1; }
done
rm -rf "$SAFEBIN"
# robustness: always exit 0, silent stderr, odd inputs, missing parser
chk_rc() { desc="$1"; shift; err="$("$@" 2>&1 >/dev/null)"; rc=$?; { [ $rc -eq 0 ] && [ -z "$err" ]; } || { echo "FAIL ($desc): rc=$rc stderr=[$err]"; fail=1; }; }
for payload in '' '{' 'null' '[]' '{"tool_input":null}' '{"tool_input":{"command":123}}' '{"tool_input":{"command":["git","commit"]}}' '{"command":"git commit"}'; do
  chk_rc "odd payload $payload" bash -c 'printf "%s" "$1" | "$2"' _ "$payload" "$GUARD"
done
chk_rc "invalid utf-8" bash -c 'printf "{\"tool_input\":{\"command\":\"echo \xe6\xff\"}}" | "$1"' _ "$GUARD"
long="$(python3 -c 'print("echo " + "x"*400000)')"
start=$(date +%s); mk_json "$long" | "$GUARD" >/dev/null; [ $(( $(date +%s) - start )) -le 3 ] || { echo "FAIL: 400 KB command took too long"; fail=1; }
# missing parser file => exit 0 and the grep fallback still asks for a plain commit
HD="$(mktemp -d)"; cp "$GUARD" "$HD/guard-git.sh"; chmod +x "$HD/guard-git.sh"
out="$(mk_json 'git commit -m x' | "$HD/guard-git.sh" 2>/dev/null)"; rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision"'; } || { echo "FAIL: missing guard_git.py must exit 0 and fall back (rc=$rc)"; fail=1; }
out="$(mk_json 'git status' | "$HD/guard-git.sh" 2>/dev/null)"; [ -z "$out" ] || { echo "FAIL: fallback fired on git status"; fail=1; }
rm -rf "$HD"
[ $fail -eq 0 ] && echo "guard-git: ${#ASK[@]} ask-cases and ${#QUIET[@]} quiet-cases OK"

# session-start: routing + stale-copy warning; remove-old-copies is a safe dry run / backup
WF="$ROOT/plugins/ai-toolkit-workflow"
H1="$(mktemp -d)"; H2="$(mktemp -d)"; SSERR="$(mktemp)"
mkdir -p "$H1/.claude/skills/code-structure" "$H1/.claude/agents"; printf -- '---\nname: code-structure\ntier: must\n---\n' > "$H1/.claude/skills/code-structure/SKILL.md"; printf '# Agent: Pre-PR Code Review\n> **Purpose:** x\n' > "$H1/.claude/agents/code-review.md"
mkdir -p "$H1/.claude/skills/ci"; printf -- '---\nname: ci\ndescription: my own CI skill\n---\n' > "$H1/.claude/skills/ci/SKILL.md"
mkdir -p "$H1/.claude/skills/my-own-skill"; echo "---" > "$H1/.claude/skills/my-own-skill/SKILL.md"
out="$(HOME="$H1" CLAUDE_PLUGIN_ROOT="$WF" bash "$WF/hooks/session-start.sh" 2>"$SSERR")"; rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$out" | grep -q "ai-toolkit workflow" && printf '%s' "$out" | grep -q "WARNING: 3 user-level skills/agents"; } || { echo "FAIL: session-start should print routing + warn about 3 stale copies (rc=$rc)"; fail=1; }
[ ! -s "$SSERR" ] || { echo "FAIL: session-start wrote to stderr"; fail=1; }
out="$(HOME="$H2" bash "$WF/hooks/session-start.sh" 2>&1)"; rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$out" | grep -q "ai-toolkit workflow" && ! printf '%s' "$out" | grep -q WARNING; } || { echo "FAIL: clean HOME must not warn (rc=$rc)"; fail=1; }
out="$(env -u HOME bash "$WF/hooks/session-start.sh" 2>&1)"; [ $? -eq 0 ] || { echo "FAIL: session-start must survive unset HOME"; fail=1; }
dry="$(HOME="$H1" bash "$WF/scripts/remove-old-copies.sh")"
{ printf '%s' "$dry" | grep -q "found   skill code-structure  \[copy\]" && printf '%s' "$dry" | grep -q "found   agent code-review  \[copy\]" && printf '%s' "$dry" | grep -q "found   skill ci  \[custom?\]" && ! printf '%s' "$dry" | grep -q my-own-skill && [ -f "$H1/.claude/skills/code-structure/SKILL.md" ]; } || { echo "FAIL: dry run must list only shipped names and move nothing"; fail=1; }
HOME="$H1" bash "$WF/scripts/remove-old-copies.sh" --apply >/dev/null
{ [ ! -e "$H1/.claude/skills/code-structure" ] && [ -f "$H1/.claude/skills/my-own-skill/SKILL.md" ] && [ -f "$H1/.claude/skills/ci/SKILL.md" ] && ls -d "$H1"/.claude/ai-toolkit-old-copies-backup-*/skills/code-structure >/dev/null 2>&1; } || { echo "FAIL: --apply must back up shipped copies only and leave user skills (incl. same-named custom ones) alone"; fail=1; }
# a second run in the same second must not nest the new backup inside the first one
mkdir -p "$H1/.claude/skills/code-structure"; printf -- '---\ntier: must\n---\n' > "$H1/.claude/skills/code-structure/SKILL.md"
HOME="$H1" bash "$WF/scripts/remove-old-copies.sh" --apply >/dev/null; HOME="$H1" bash "$WF/scripts/remove-old-copies.sh" --apply --all >/dev/null
{ [ ! -e "$H1/.claude/skills/ci" ] && [ "$(find "$H1/.claude" -path '*backup*/skills/*/skills' | wc -l | tr -d ' ')" = 0 ] && [ "$(ls -d "$H1"/.claude/ai-toolkit-old-copies-backup-* | wc -l | tr -d ' ')" -ge 2 ]; } || { echo "FAIL: re-runs must use a fresh backup dir and --all must move custom items"; fail=1; }
rm -rf "$H1" "$H2" "$SSERR"
[ $fail -eq 0 ] && echo "session-start + remove-old-copies OK"

# hooks.json wiring: run every registered hook command exactly as Claude Code would (bash, placeholders expanded)
wire="$(mktemp -d)"; mkdir -p "$wire/proj"; : > "$wire/proj/pom.xml"
python3 - "$ROOT" > "$wire/cmds.txt" <<'PYEOF'
import glob, json, os, sys
root = sys.argv[1]
for hj in sorted(glob.glob(os.path.join(root, "plugins", "*", "hooks", "hooks.json"))):
    plugin = os.path.dirname(os.path.dirname(hj))
    for event, groups in json.load(open(hj)).get("hooks", {}).items():
        for g in groups:
            for h in g.get("hooks", []):
                print("\t".join([plugin, event, h["command"]]))
PYEOF
wired=0
while IFS=$'\t' read -r plugin event command; do
  wired=$((wired + 1))
  expanded="${command//\$\{CLAUDE_PLUGIN_ROOT\}/$plugin}"
  out="$(printf '{"tool_input":{"command":"ls"}}' | CLAUDE_PROJECT_DIR="$wire/proj" CLAUDE_PLUGIN_ROOT="$plugin" sh -c "$expanded" 2>"$wire/err")"; rc=$?
  { [ $rc -eq 0 ] && [ ! -s "$wire/err" ]; } || { echo "FAIL (hook wiring $event): $plugin -> rc=$rc stderr=[$(cat "$wire/err")]"; fail=1; }
  if [ "$event" = SessionStart ] && [ -z "$out" ] && [[ "$plugin" == *workflow ]]; then echo "FAIL: workflow SessionStart printed nothing"; fail=1; fi
done < "$wire/cmds.txt"
[ "$wired" -ge 5 ] || { echo "FAIL: expected >= 5 registered hooks, found $wired"; fail=1; }
rm -rf "$wire"
[ $fail -eq 0 ] && echo "hooks.json wiring OK ($wired hook commands executed)"

# language detectors (project dir containing a space on purpose)
tmp="$(mktemp -d)"; d="$tmp/my project"; mkdir -p "$d"
check_detect() { # plugin touchcmd expect(yes|no) label
  p="$ROOT/plugins/$1/hooks/detect-and-route.sh"; rm -rf "$d"; mkdir -p "$d"; (cd "$d" && eval "$2")
  out="$(CLAUDE_PROJECT_DIR="$d" CLAUDE_PLUGIN_ROOT="$ROOT/plugins/$1" "$p")"
  if [ "$3" = yes ] && [ -z "$out" ]; then echo "FAIL (should route): $1 $4"; fail=1; fi
  if [ "$3" = no ]  && [ -n "$out" ]; then echo "FAIL (should be silent): $1 $4"; fail=1; fi
}
check_detect ai-toolkit-java-design 'touch pom.xml' yes pom.xml
check_detect ai-toolkit-java-design 'touch build.gradle.kts' yes build.gradle.kts
check_detect ai-toolkit-java-design 'touch settings.gradle' yes settings.gradle
check_detect ai-toolkit-java-design 'touch package.json' no package.json
check_detect ai-toolkit-java-design 'mkdir -p services/billing && touch services/billing/pom.xml' yes monorepo-services
check_detect ai-toolkit-java-design 'mkdir -p backend && touch backend/build.gradle.kts' yes monorepo-subdir
check_detect ai-toolkit-java-design 'mkdir -p node_modules/x && touch node_modules/x/pom.xml' no node_modules-only
check_detect ai-toolkit-java-design ':' yes empty-dir
check_detect ai-toolkit-java-design 'git init -q . && touch README.md .gitignore' yes empty-repo-with-readme
check_detect ai-toolkit-java-design 'mkdir -p src && touch src/main.go' no unrelated-project
check_detect ai-toolkit-python-design 'touch pyproject.toml' yes pyproject.toml
check_detect ai-toolkit-python-design 'touch requirements-dev.txt' yes requirements-dev.txt
check_detect ai-toolkit-python-design 'touch Pipfile' yes Pipfile
check_detect ai-toolkit-python-design 'touch setup.cfg' yes setup.cfg
check_detect ai-toolkit-python-design 'touch pom.xml' no pom.xml
check_detect ai-toolkit-python-design 'touch pom.xml && mkdir -p docs && touch docs/requirements.txt docs/index.md' no java-repo-with-mkdocs-requirements
check_detect ai-toolkit-python-design 'mkdir -p tools && touch tools/requirements.txt tools/run.py' yes subdir-with-python-code
check_detect ai-toolkit-python-design 'mkdir -p services/api && touch services/api/pyproject.toml' yes monorepo-services
check_detect ai-toolkit-react-native-design "echo '{\"dependencies\":{\"react-native\":\"0.76\"}}' > package.json" yes react-native
check_detect ai-toolkit-react-native-design "echo '{\"dependencies\":{\"react\":\"18\"}}' > package.json" no react-only
check_detect ai-toolkit-react-native-design "echo '{\"dependencies\":{\"react-native-svg\":\"1\"}}' > package.json" no react-native-svg-only
rm -rf "$tmp"
[ $fail -eq 0 ] && echo "detectors OK" || echo "HOOK TESTS FAILED"
exit $fail

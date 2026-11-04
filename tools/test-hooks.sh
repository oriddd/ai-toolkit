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
  $'cd /x\ngit push' $'echo hi\ngit commit -m x' $'git add .\ngit commit -m "msg"' $'git add . \\\n && git commit -m x'
  '{ git commit -m x; }' 'if true; then git commit -m x; fi' 'for f in a; do git push; done' '! git commit -m x'
  'echo `git commit -m x`' 'sudo -u bob git commit -m x' 'env -i git commit -m x' 'nice -n 5 git push' 'timeout 5 git push' 'xargs -n1 git push'
  'bash -lc "git commit -m x"' 'sh -ec "git push"' 'bash --login -c "git commit -m x"' 'eval git commit -m x' 'bash -c "bash -c \"git push\""'
  'gh -R a/b pr create' 'gh release create v1' 'gh api -X POST repos/a/b/pulls' 'git.exe commit -m x' 'C:\\Program\ Files\\Git\\git.exe push'
  'npm version patch' 'npm publish' 'mvn release:prepare' 'mvn -B release:perform' 'mvn deploy'
)
QUIET=(
  'git status' 'git diff' 'git diff --stat' 'git diff commit' 'git log --oneline' 'git log --grep "git commit"' 'git show HEAD'
  'git branch' 'git branch -a' 'git checkout -b x' 'git switch main' 'git add -A' 'git fetch' 'git pull' 'git remote -v'
  'git stash list' 'git tag' 'git tag -l' 'git tag --list "v*"' 'git reset --soft HEAD~1' 'git reset HEAD file'
  'echo "use git commit later"' 'echo git commit' 'cat commit.txt' 'grep -r "git push" docs' 'mvn -B verify' 'npm run verify'
  'gh pr view 12' 'gh pr list' 'ls -la' 'python3 -m pytest'
  'git merge --abort' 'git rebase --abort' 'git rebase --continue' 'git cherry-pick --abort' 'git push --dry-run' 'git commit --dry-run'
  'git merge --no-commit feature' 'git commit -h' 'gh pr create --help' 'git rebase --show-current-patch' 'git am --abort'
  $'git status\ngit diff' 'git diff | grep commit' 'git status # commit later' 'git commit-graph verify' 'git merge-base a b'
  'npm run build' 'npm test' 'mvn -B verify' 'mvn dependency:tree' 'gh api repos/a/b/pulls' 'gh api -X GET repos/a/b'
)
for c in "${ASK[@]}";   do expect_ask "$c";   done
for c in "${QUIET[@]}"; do expect_quiet "$c"; done
# a clean command whose description mentions git commit must not fire
out="$(python3 -c 'import json; print(json.dumps({"tool_input":{"command":"ls","description":"git commit later"}}))' | "$GUARD")"
[ -z "$out" ] || { echo "FAIL: description text triggered the guard"; fail=1; }
# fallback path (no python3) must still catch the common cases
SAFEBIN="$(mktemp -d)"; for b in cat dirname grep bash sh env; do ln -s "$(command -v $b)" "$SAFEBIN/$b" 2>/dev/null; done
out="$(mk_json 'git commit -m x' | PATH="$SAFEBIN" "$GUARD")"
printf '%s' "$out" | grep -q '"permissionDecision": "ask"' || printf '%s' "$out" | grep -q 'permissionDecision' || { echo "FAIL: no-python fallback missed git commit"; fail=1; }
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
cp -R "$ROOT/plugins/ai-toolkit-workflow/hooks" "$(mktemp -d)/h" 2>/dev/null
HD="$(mktemp -d)"; cp "$GUARD" "$HD/guard-git.sh"; chmod +x "$HD/guard-git.sh"
out="$(mk_json 'git commit -m x' | "$HD/guard-git.sh" 2>/dev/null)"; rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision"'; } || { echo "FAIL: missing guard_git.py must exit 0 and fall back (rc=$rc)"; fail=1; }
out="$(mk_json 'git status' | "$HD/guard-git.sh" 2>/dev/null)"; [ -z "$out" ] || { echo "FAIL: fallback fired on git status"; fail=1; }
rm -rf "$HD"
[ $fail -eq 0 ] && echo "guard-git: ${#ASK[@]} ask-cases and ${#QUIET[@]} quiet-cases OK"

# session-start: routing + stale-copy warning; remove-old-copies is a safe dry run / backup
WF="$ROOT/plugins/ai-toolkit-workflow"
H1="$(mktemp -d)"; H2="$(mktemp -d)"
mkdir -p "$H1/.claude/skills/code-structure" "$H1/.claude/agents"; echo "---" > "$H1/.claude/skills/code-structure/SKILL.md"; echo "---" > "$H1/.claude/agents/code-review.md"
mkdir -p "$H1/.claude/skills/my-own-skill"; echo "---" > "$H1/.claude/skills/my-own-skill/SKILL.md"
out="$(HOME="$H1" CLAUDE_PLUGIN_ROOT="$WF" bash "$WF/hooks/session-start.sh" 2>/tmp/ss.err)"; rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$out" | grep -q "ai-toolkit workflow" && printf '%s' "$out" | grep -q "WARNING: 2 user-level skills/agents"; } || { echo "FAIL: session-start should print routing + warn about 2 stale copies (rc=$rc)"; fail=1; }
[ ! -s /tmp/ss.err ] || { echo "FAIL: session-start wrote to stderr"; fail=1; }
out="$(HOME="$H2" bash "$WF/hooks/session-start.sh" 2>&1)"; rc=$?
{ [ $rc -eq 0 ] && printf '%s' "$out" | grep -q "ai-toolkit workflow" && ! printf '%s' "$out" | grep -q WARNING; } || { echo "FAIL: clean HOME must not warn (rc=$rc)"; fail=1; }
out="$(env -u HOME bash "$WF/hooks/session-start.sh" 2>&1)"; [ $? -eq 0 ] || { echo "FAIL: session-start must survive unset HOME"; fail=1; }
dry="$(HOME="$H1" bash "$WF/scripts/remove-old-copies.sh")"
{ printf '%s' "$dry" | grep -q "found   skill code-structure" && printf '%s' "$dry" | grep -q "found   agent code-review" && ! printf '%s' "$dry" | grep -q my-own-skill && [ -f "$H1/.claude/skills/code-structure/SKILL.md" ]; } || { echo "FAIL: dry run must list only shipped names and move nothing"; fail=1; }
HOME="$H1" bash "$WF/scripts/remove-old-copies.sh" --apply >/dev/null
{ [ ! -e "$H1/.claude/skills/code-structure" ] && [ -f "$H1/.claude/skills/my-own-skill/SKILL.md" ] && ls -d "$H1"/.claude/ai-toolkit-old-copies-backup-*/skills/code-structure >/dev/null 2>&1; } || { echo "FAIL: --apply must back up shipped copies only and leave user skills alone"; fail=1; }
rm -rf "$H1" "$H2" /tmp/ss.err
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
det() { rm -rf "$d"/* "$d"/.[!.]* 2>/dev/null; "$@"; }
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
check_detect ai-toolkit-python-design 'touch pyproject.toml' yes pyproject.toml
check_detect ai-toolkit-python-design 'touch requirements-dev.txt' yes requirements-dev.txt
check_detect ai-toolkit-python-design 'touch Pipfile' yes Pipfile
check_detect ai-toolkit-python-design 'touch setup.cfg' yes setup.cfg
check_detect ai-toolkit-python-design 'touch pom.xml' no pom.xml
check_detect ai-toolkit-react-native-design "echo '{\"dependencies\":{\"react-native\":\"0.76\"}}' > package.json" yes react-native
check_detect ai-toolkit-react-native-design "echo '{\"dependencies\":{\"react\":\"18\"}}' > package.json" no react-only
check_detect ai-toolkit-react-native-design "echo '{\"dependencies\":{\"react-native-svg\":\"1\"}}' > package.json" no react-native-svg-only
rm -rf "$tmp"
[ $fail -eq 0 ] && echo "detectors OK" || echo "HOOK TESTS FAILED"
exit $fail

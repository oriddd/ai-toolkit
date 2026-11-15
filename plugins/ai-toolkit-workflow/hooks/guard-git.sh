#!/usr/bin/env bash
# PreToolUse(Bash): require confirmation before commits, pushes, tags, stashes, discards and history rewrites.
# Policy: never commit/push until the developer asks (skill: completion-gate).
# Best-effort safety net for Claude's Bash tool — see guard_git.py. Always exits 0.
d="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
input="$(cat)"

# Preferred: the parser (needs python3 >= 3.7).
if [ -f "$d/guard_git.py" ] && command -v python3 >/dev/null 2>&1 \
   && python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 7) else 1)' >/dev/null 2>&1; then
  out="$(printf '%s' "$input" | python3 "$d/guard_git.py" 2>/dev/null)"
  if [ $? -eq 0 ]; then
    [ -n "$out" ] && printf '%s\n' "$out"
    exit 0
  fi
fi

# Fallback (no usable python3, e.g. Windows Git Bash): a smaller pure-bash parser. It extracts the
# command from the JSON, splits it on unquoted ; & | ( ) ` and newlines, strips quotes and checks
# each statement's program and subcommand — so `echo "git commit"` and `git tag -l` stay quiet while
# quoted paths and multi-line commands are caught. It does not handle heredocs, aliases or substitutions.
LC_ALL=C
ask() {
  cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"ai-toolkit policy: do not commit, push, tag, stash, discard work, release or rewrite history until the developer asks. Approve only if you asked for it. Headless runs (claude -p) have nobody to approve, so the command is refused: run it yourself, run interactively, or pass --permission-prompt-tool."}}
JSON
  exit 0
}

# --- extract tool_input.command and undo JSON escapes (first 20000 chars only) ---
s="${input:0:20000}"
case "$s" in *'"tool_input"'*) s="${s#*\"tool_input\"}" ;; *) exit 0 ;; esac
case "$s" in *'"command"'*) s="${s#*\"command\"}" ;; *) exit 0 ;; esac
s="${s#*:}"; s="${s#"${s%%[![:space:]]*}"}"
[ "${s:0:1}" = '"' ] || exit 0
cmd=""; i=1; n=${#s}
while [ $i -lt $n ]; do
  c="${s:i:1}"
  if [ "$c" = '\' ]; then
    i=$((i + 1)); e="${s:i:1}"
    case "$e" in n) cmd+=$'\n' ;; t) cmd+=$'\t' ;; r) cmd+=$'\r' ;; u) cmd+='?'; i=$((i + 4)) ;; *) cmd+="$e" ;; esac
  elif [ "$c" = '"' ]; then
    break
  else
    cmd+="$c"
  fi
  i=$((i + 1))
done
cmd="${cmd//\$\{IFS\}/ }"; cmd="${cmd//\$IFS/ }"

# --- statement checks ---
text_re='(^|[^[:alnum:]_.-])(git|gh)[[:space:]].*(commit|push|tag|stash|rebase|merge|revert|publish)'

words=()
in_list() { local x="$1"; shift; local y; for y in "$@"; do [ "$x" = "$y" ] && return 0; done; return 1; }
base() { local b="${1##*/}"; b="${b##*\\}"; case "$b" in *.exe|*.EXE) b="${b%????}" ;; esac; printf '%s' "$b"; }
value_opt() { in_list "$1" -m --message -F --file -C -c -t --template --author --date --fixup --squash --cleanup --trailer -o --push-option --repo --exec -s --strategy -X --strategy-option --onto; }

check_git() { # words after "git"
  local a=("$@") i=0 sub rest f p
  while [ $i -lt ${#a[@]} ]; do
    case "${a[i]}" in -C|-c|--git-dir|--work-tree|--namespace|--exec-path|--config-env) i=$((i + 2)) ;; -*) i=$((i + 1)) ;; *) break ;; esac
  done
  sub="${a[i]:-}"; rest=("${a[@]:i+1}")
  local flags=() pos=() skip=0 paths=0
  for p in "${rest[@]}"; do
    if [ $paths -ge 1 ]; then paths=2; break; fi
    if [ $skip -eq 1 ]; then skip=0; continue; fi
    [ "$p" = "--" ] && { paths=1; continue; }
    case "$p" in -*) flags+=("$p"); value_opt "$p" && skip=1 ;; *) pos+=("$p") ;; esac
  done
  [ $paths -eq 2 ] || paths=0
  case "$sub" in
    commit|push|rebase|cherry-pick|merge|am|revert|commit-tree|update-ref|filter-branch|filter-repo|send-email|fast-import)
      if [ ${#rest[@]} -eq 1 ] && in_list "${rest[0]}" --abort --continue --skip --quit --show-current-patch -h --help; then return 1; fi
      for f in "${flags[@]}"; do
        [ "$sub" = commit ] && [ "$f" = --dry-run ] && return 1
        [ "$sub" = push ] && in_list "$f" --dry-run -n && return 1
        in_list "$sub" merge cherry-pick revert && [ "$f" = --no-commit ] && return 1
      done
      return 0 ;;
    tag)
      [ ${#pos[@]} -gt 0 ] || return 1
      for f in "${flags[@]}"; do in_list "$f" -l --list -n --contains --no-contains --merged --no-merged --points-at -v --verify && return 1; done
      return 0 ;;
    reset)
      for f in "${flags[@]}"; do in_list "$f" --hard --merge --keep --soft && return 0; done
      { [ ${#pos[@]} -gt 1 ] || [ $paths -eq 2 ]; } && return 1
      for p in "${pos[@]}"; do case "$p" in *'~'*|*'^'*|@\{*|ORIG_HEAD|FETCH_HEAD) return 0 ;; esac; done
      return 1 ;;
    stash) [ ${#rest[@]} -eq 0 ] && return 0; in_list "${rest[0]}" list show create -h --help && return 1; return 0 ;;
    branch) for f in "${flags[@]}"; do in_list "$f" -f --force -M -C -D && return 0; done; return 1 ;;
    checkout)
      for f in "${flags[@]}"; do in_list "$f" -B -f --force && return 0; done
      [ $paths -eq 2 ] && return 0
      local cpos=() cskip=0
      for p in "${rest[@]}"; do
        [ "$p" = "--" ] && break
        if [ $cskip -eq 1 ]; then cskip=0; continue; fi
        case "$p" in -b|-B|--orphan) cskip=1 ;; -*) ;; *) cpos+=("$p") ;; esac
      done
      [ ${#cpos[@]} -gt 1 ] && return 0
      in_list . "${cpos[@]}" && return 0; return 1 ;;
    switch) for f in "${flags[@]}"; do in_list "$f" -C --force-create -f --force --discard-changes && return 0; done; return 1 ;;
    restore)
      local staged=0
      for f in "${flags[@]}"; do in_list "$f" -h --help && return 1; in_list "$f" -S --staged && staged=1; done
      [ $staged -eq 0 ] && return 0
      for f in "${flags[@]}"; do in_list "$f" -W --worktree && return 0; done; return 1 ;;
    clean)
      for f in "${flags[@]}"; do in_list "$f" -h --help --dry-run && return 1; [[ "$f" =~ ^-[A-Za-z]*n[A-Za-z]*$ ]] && return 1; done
      return 0 ;;
    pull) for f in "${flags[@]}"; do case "$f" in -r|--rebase|--rebase=true|--rebase=merges|--rebase=interactive) return 0 ;; esac; done; return 1 ;;
    svn) in_list "${rest[0]:-}" dcommit rebase commit-diff set-tree && return 0; return 1 ;;
    subtree) in_list "${pos[0]:-}" add merge pull push && return 0; return 1 ;;
    submodule)
      local inner=() on=0
      for p in "${rest[@]}"; do
        if [ $on -eq 1 ]; then case "$p" in --recursive|-q|--quiet) ;; *) inner+=("$p") ;; esac; elif [ "$p" = foreach ]; then on=1; fi
      done
      [ ${#inner[@]} -gt 0 ] && fb_risky "${inner[*]}" 1 && return 0; return 1 ;;
  esac
  return 1
}

check_gh() {
  local a=("$@") i=0
  while [ $i -lt ${#a[@]} ]; do case "${a[i]}" in -R|--repo|--hostname) i=$((i + 2)) ;; -*) i=$((i + 1)) ;; *) break ;; esac; done
  local g="${a[i]:-}" v="${a[i+1]:-}" n=$(( ${#a[@]} - i ))
  if [ "$g" = api ] && [ "$v" = graphql ]; then
    local j val
    for ((j = i + 2; j < ${#a[@]}; j++)); do
      case "${a[j]}" in
        --input|--input=*) return 0 ;;
        -f|-F|--field|--raw-field) val="${a[j+1]:-}" ;;
        --field=*|--raw-field=*) val="${a[j]#*=}" ;;
        -f?*|-F?*) val="${a[j]:2}" ;;
        *) continue ;;
      esac
      [[ "$val" =~ (^|[^[:alnum:]_])mutation([^[:alnum:]_]|$) ]] && return 0
      case "${val#*=}" in @*) return 0 ;; esac
    done
    return 1
  fi
  if [ "$g" = api ]; then
    local j m="" body=0
    for ((j = i + 1; j < ${#a[@]}; j++)); do
      case "${a[j]}" in
        -X|--method) m="${a[j+1]:-}" ;; --method=*) m="${a[j]#--method=}" ;; -X?*) m="${a[j]#-X}" ;;
        -f|-F|--field|--raw-field|--input|--field=*|--raw-field=*|--input=*|-f?*|-F?*) body=1 ;;
      esac
    done
    if [ -n "$m" ]; then case "$m" in [Pp][Oo][Ss][Tt]|[Pp][Uu][Tt]|[Pp][Aa][Tt][Cc][Hh]|[Dd][Ee][Ll][Ee][Tt][Ee]) return 0 ;; esac; return 1; fi
    [ $body -eq 1 ]; return
  fi
  [ $n -eq 3 ] && in_list "${a[i+2]}" --help -h && return 1
  case "$g:$v" in
    pr:create|pr:merge|pr:review|pr:ready|pr:close|pr:reopen|pr:comment|pr:edit|pr:update-branch) return 0 ;;
    release:create|release:upload|release:edit|release:delete|release:delete-asset) return 0 ;;
    repo:create|repo:delete|repo:edit|repo:rename|repo:archive|repo:unarchive|repo:sync|repo:fork) return 0 ;;
    workflow:run|workflow:enable|workflow:disable|run:rerun|run:cancel|run:delete) return 0 ;;
    issue:create|issue:close|issue:reopen|issue:comment|issue:edit|issue:delete|issue:transfer) return 0 ;;
    secret:set|secret:delete|variable:set|variable:delete) return 0 ;;
  esac
  return 1
}

check_statement() { # $1 depth, words in global array "words"
  local depth="$1" i=0 j prog w
  local ws=("${words[@]}")
  while [ $i -lt ${#ws[@]} ]; do
    case "${ws[i]}" in then|do|else|elif|if|while|until|'{'|'}'|'!'|time) i=$((i + 1)) ;;
      [A-Za-z_]*=*) [[ "${ws[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && i=$((i + 1)) || break ;;
      *) break ;; esac
  done
  [ $i -lt ${#ws[@]} ] || return 1
  prog="$(base "${ws[i]}")"
  if in_list "$prog" sudo command env nohup exec builtin xargs nice ionice timeout stdbuf doas watch; then
    for ((j = i + 1; j < ${#ws[@]} && j < i + 9; j++)); do
      w="$(base "${ws[j]}")"
      if in_list "$w" git gh npm yarn pnpm bun mvn mvnw mvn.cmd mvnw.cmd gradle gradlew gradlew.bat twine poetry cargo uv sh bash zsh dash ksh; then i=$j; prog="$w"; break; fi
      case "${ws[j]}" in *' '*) fb_risky "${ws[j]}" $((depth + 1)) && return 0 ;; esac
    done
  fi
  local args=("${ws[@]:i+1}")
  case "$prog" in
    git) check_git "${args[@]}" && return 0 ;;
    gh) check_gh "${args[@]}" && return 0 ;;
    npm|yarn|pnpm|bun)
      local pos=() skip=0
      for w in "${args[@]}"; do
        if [ $skip -eq 1 ]; then skip=0; continue; fi
        case "$w" in --prefix|-C|--dir|--cwd|--filter|-F|--workspace|-w|--registry) skip=1 ;; -*) ;; *) pos+=("$w") ;; esac
      done
      for w in "${args[@]}"; do in_list "$w" -h --help && return 1; done
      in_list "${pos[0]:-}" publish version release && return 0
      [ "$prog" = yarn ] && [ "${pos[0]:-}" = npm ] && [ "${pos[1]:-}" = publish ] && return 0 ;;
    mvn|mvnw|mvn.cmd|mvnw.cmd|mvnd)
      local skip=0
      for w in "${args[@]}"; do
        if [ $skip -eq 1 ]; then skip=0; continue; fi
        case "$w" in
          -f|--file|-pl|--projects|-rf|--resume-from|-P|--activate-profiles|-s|--settings|-gs|--global-settings|-t|--toolchains|-gt|--global-toolchains|-T|--threads|-l|--log-file|-b|--builder|-D|--define|-emp|--encrypt-master-password|-ep|--encrypt-password) skip=1 ;;
          -*) ;;
          deploy|deploy:*|release:*|*:deploy:*|*:release:*|*:maven-deploy-plugin:*|*:maven-release-plugin:*|maven-deploy-plugin:*|maven-release-plugin:*) return 0 ;;
        esac
      done ;;
    gradle|gradlew|gradlew.bat)
      local skip=0
      for w in "${args[@]}"; do
        if [ $skip -eq 1 ]; then skip=0; continue; fi
        case "$w" in
          -x|--exclude-task|-p|--project-dir|-b|--build-file|-c|--settings-file|-g|--gradle-user-home|-I|--init-script|--include-build|--project-cache-dir) skip=1 ;;
          -*) ;;
          *) case "${w##*:}" in *MavenLocal) ;; publish*) return 0 ;; esac ;;
        esac
      done ;;
    twine) [ "${args[0]:-}" = upload ] && return 0 ;;
    poetry|cargo|uv|hatch|flit|pdm) [ "${args[0]:-}" = publish ] && return 0 ;;
    sh|bash|zsh|dash|ksh|fish)
      local seen=0 plain=0
      for w in "${args[@]}"; do
        if [ $seen -eq 1 ]; then case "$w" in -*|+*) ;; *) fb_risky "$w" $((depth + 1)) && return 0 ;; esac
        elif [[ "$w" =~ ^-[A-Za-z]*c[A-Za-z]*$ ]]; then seen=1
        else case "$w" in -*|+*) ;; *) plain=1 ;; esac; fi
      done
      # a shell reading stdin (`... | sh`): assume the worst if the whole command mentions a risky git call
      [ $seen -eq 0 ] && [ $plain -eq 0 ] && [[ "$cmd" =~ $text_re ]] && return 0 ;;
    \$*) for w in "${args[@]:0:3}"; do in_list "$w" commit push tag stash rebase cherry-pick merge am revert publish deploy && return 0; done ;;
    eval) fb_risky "${args[*]}" $((depth + 1)) && return 0 ;;
  esac
  return 1
}

fb_risky() { # $1 command text, $2 depth; returns 0 when risky
  local t="$1" depth="${2:-0}" k=0 len c q="" w="" have=0
  [ "$depth" -gt 3 ] && return 1
  len=${#t}
  words=()
  while [ $k -le $len ]; do
    c="${t:k:1}"
    if [ -n "$q" ]; then
      if [ "$c" = "$q" ]; then q=""
      elif [ "$q" = '"' ] && [ "$c" = '\' ]; then k=$((k + 1)); w+="${t:k:1}"
      else w+="$c"; fi
    elif [ $k -eq $len ] || [[ "$c" == [\;\&\|\(\)\`$'\n'] ]]; then
      [ $have -eq 1 ] && words+=("$w"); w=""; have=0
      [ ${#words[@]} -gt 0 ] && check_statement "$depth" && return 0
      words=()
    elif [[ "$c" == [[:space:]] ]]; then
      [ $have -eq 1 ] && words+=("$w"); w=""; have=0
    elif [ "$c" = "'" ] || [ "$c" = '"' ]; then q="$c"; have=1
    elif [ "$c" = '\' ]; then k=$((k + 1)); [ "${t:k:1}" != $'\n' ] && { w+="${t:k:1}"; have=1; }
    elif [ "$c" = '#' ] && [ $have -eq 0 ]; then
      while [ $k -lt $len ] && [ "${t:k:1}" != $'\n' ]; do k=$((k + 1)); done; continue
    elif [[ "$c" == [\<\>] ]]; then
      [ $have -eq 1 ] && [[ ! "$w" =~ ^[0-9]+$ ]] && words+=("$w"); w=""; have=0
      while [[ "${t:k+1:1}" == [\<\>\&] ]]; do k=$((k + 1)); done
      while [[ "${t:k+1:1}" == [[:space:]] ]]; do k=$((k + 1)); done
      while [ $((k + 1)) -lt $len ] && [[ "${t:k+1:1}" != [[:space:]\;\&\|\(\)] ]]; do k=$((k + 1)); done
    else w+="$c"; have=1; fi
    k=$((k + 1))
  done
  [ -n "$q" ] && [[ "$t" =~ $text_re ]] && return 0  # unbalanced quotes: be conservative
  return 1
}

fb_risky "$cmd" 0 && ask
exit 0

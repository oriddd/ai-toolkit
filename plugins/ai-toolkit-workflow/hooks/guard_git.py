#!/usr/bin/env python3
"""PreToolUse(Bash): ask before commits, pushes, tags, stashes, discards, history rewrites and releases.

Policy (skill: completion-gate): never commit/push/tag/stash/rebase/release until the developer asks.
Reads the tool-call JSON on stdin; prints a permissionDecision "ask" JSON when the command would
create a commit/tag, stash, restore or discard work, publish, or rewrite history. Parses the command (quotes,
newlines, operators, comments, heredocs, shell -c strings, wrappers, env prefixes) instead of grepping
text, so quoted paths, multi-line commands and chains are handled while `echo "git commit"` is not.

This is a best-effort safety net for Claude's Bash tool, not a security boundary: it cannot see
variable indirection, scripts that commit internally, or other tools. When it cannot tell, it asks.
Always exits 0 — a bug here must never block a developer's session.
"""
import json
import os
import re
import shlex
import subprocess
import sys

ASK = {"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": (
        "ai-toolkit policy: do not commit, push, tag, stash, discard work, release or rewrite history until the developer "
        "asks. Approve only if you asked for it. Headless runs (claude -p) have nobody to approve, so the "
        "command is refused: run it yourself, run interactively, or pass --permission-prompt-tool."),
}}
OPERATORS = set(";&|()")
KEYWORDS = {"then", "do", "else", "elif", "if", "while", "until", "{", "}", "!", "time"}
WRAPPERS = {"sudo", "command", "env", "nohup", "exec", "builtin", "xargs", "nice", "ionice", "timeout", "stdbuf",
            "doas", "watch", "caffeinate", "chronic", "unbuffer", "flock", "setsid", "script"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "fish", "ash", "mksh"}
MAX_DEPTH = 6

GIT_OPTS_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix", "--config-env"}
GIT_ALWAYS = {"commit", "push", "rebase", "cherry-pick", "merge", "am", "revert",
              "commit-tree", "update-ref", "filter-branch", "filter-repo", "send-email", "fast-import"}
# Flags that turn a GIT_ALWAYS command into a no-op/inspection — only when they are the *only* argument.
SOLE_SAFE_FLAGS = {"--abort", "--continue", "--skip", "--quit", "--show-current-patch", "-h", "--help"}
DRY_RUN_FLAGS = {"commit": {"--dry-run"}, "push": {"--dry-run", "-n"}}  # -n is --no-verify for commit
NO_COMMIT_SUBS = {"merge", "cherry-pick", "revert"}
# Options whose value is a separate token, so the value must never be read as a flag (`git commit -m --abort`).
GIT_VALUE_OPTS = {"-m", "--message", "-F", "--file", "-C", "--reuse-message", "-c", "--reedit-message", "-t",
                  "--template", "--author", "--date", "--fixup", "--squash", "--cleanup", "--trailer",
                  "--pathspec-from-file", "-o", "--push-option", "--repo", "--receive-pack", "--exec", "-s",
                  "--strategy", "-X", "--strategy-option", "--onto", "--into-name", "-x", "--exec-cmd"}
TAG_LIST_FLAGS = {"-l", "--list", "-n", "--contains", "--no-contains", "--merged", "--no-merged", "--points-at", "-v", "--verify"}
STASH_QUIET = {"list", "show", "create", "-h", "--help"}
SUBTREE_WRITE = {"add", "merge", "pull", "push"}
# Built-in git subcommands that need no alias lookup.
GIT_KNOWN = GIT_ALWAYS | {
    "status", "diff", "log", "show", "branch", "checkout", "switch", "add", "fetch", "pull", "remote", "stash", "tag",
    "reset", "restore", "rm", "mv", "grep", "blame", "config", "init", "clone", "ls-files", "ls-remote", "ls-tree",
    "rev-parse", "rev-list", "describe", "shortlog", "reflog", "worktree", "submodule", "subtree", "svn", "help",
    "version", "cat-file", "for-each-ref", "merge-base", "commit-graph", "format-patch", "bisect", "clean", "notes",
    "gc", "fsck", "show-ref", "symbolic-ref", "name-rev", "archive", "apply", "range-diff", "whatchanged", "var",
    "check-ignore", "check-attr", "hash-object", "count-objects", "sparse-checkout", "maintenance", "lfs", "difftool",
    "mergetool", "cherry", "request-pull", "verify-commit", "verify-tag", "credential", "",
}

GH_PAIRS = {
    "pr": {"create", "merge", "review", "ready", "close", "reopen", "comment", "edit", "lock", "unlock", "update-branch"},
    "release": {"create", "upload", "edit", "delete", "delete-asset"},
    "repo": {"create", "delete", "edit", "rename", "archive", "unarchive", "sync", "fork", "set-default"},
    "workflow": {"run", "enable", "disable"},
    "run": {"rerun", "cancel", "delete"},
    "issue": {"create", "close", "reopen", "comment", "edit", "delete", "transfer", "lock", "unlock", "pin", "unpin"},
    "secret": {"set", "delete"},
    "variable": {"set", "delete"},
    "label": {"create", "edit", "delete", "clone"},
    "gist": {"create", "edit", "delete"},
    "cache": {"delete"},
}
GH_WRITE_METHODS = {"POST", "PUT", "PATCH", "DELETE"}
GH_BODY_FLAGS = {"-f", "-F", "--field", "--raw-field", "--input"}

JS_PMS = {"npm", "yarn", "pnpm", "bun"}
JS_VALUE_OPTS = {"--prefix", "-C", "--dir", "--cwd", "--filter", "-F", "--workspace", "-w", "--registry", "--userconfig"}
JS_PUBLISH = {"publish", "version", "release"}
MAVEN = {"mvn", "mvnw", "mvn.cmd", "mvnw.cmd", "mvnd"}
MAVEN_VALUE_OPTS = {"-f", "--file", "-pl", "--projects", "-rf", "--resume-from", "-P", "--activate-profiles", "-s",
                    "--settings", "-gs", "--global-settings", "-t", "--toolchains", "-gt", "--global-toolchains", "-T",
                    "--threads", "-l", "--log-file", "-b", "--builder", "-D", "--define", "-emp",
                    "--encrypt-master-password", "-ep", "--encrypt-password"}
MAVEN_PUBLISH_PLUGINS = {"deploy", "release", "maven-deploy-plugin", "maven-release-plugin"}
GRADLE = {"gradle", "gradlew", "gradlew.bat", "gradle.bat"}
GRADLE_VALUE_OPTS = {"-x", "--exclude-task", "-p", "--project-dir", "-b", "--build-file", "-c", "--settings-file",
                     "-g", "--gradle-user-home", "-I", "--init-script", "--include-build", "--project-cache-dir"}
OTHER_PUBLISH = {("twine", "upload"), ("poetry", "publish"), ("cargo", "publish"), ("uv", "publish"),
                 ("hatch", "publish"), ("flit", "publish"), ("gem", "push"), ("pdm", "publish")}
KNOWN_PROGS = {"git", "gh"} | JS_PMS | MAVEN | GRADLE | SHELLS | {p for p, _ in OTHER_PUBLISH}

ENV_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
IFS_RE = re.compile(r"\$\{IFS\}|\$IFS(?![A-Za-z0-9_])")  # `git commit$IFS-m x` splits into words at run time
GRAPHQL_MUTATION = re.compile(r"\bmutation\b")
RISKY_WORDS = {"commit", "push", "tag", "stash", "rebase", "cherry-pick", "merge", "am", "revert", "publish", "deploy", "release"}
BUDGET = [2000]  # max parse calls per hook run; nested wrappers/shells cannot blow up the runtime
# Conservative text match used when the command cannot be parsed or nests too deep.
FALLBACK_RE = re.compile(r"(^|[^A-Za-z0-9_.-])(git|gh)([^A-Za-z0-9_.-][^;&|\n]*)?[^A-Za-z0-9_-]"
                         r"(commit|push|tag|stash|rebase|cherry-pick|merge|am|revert|publish|release)([^A-Za-z0-9_-]|$)")
# A program name produced by substitution, e.g. `$(echo git) push` or `` `which git` commit ``.
SUBST_PROG = re.compile(r"(?:^|[;&|(\n])\s*(\$\([^()]*\bgit\b[^()]*\)|`[^`]*\bgit\b[^`]*`)\s+[^;&|\n]*\b(commit|push|tag|stash|rebase|cherry-pick|merge|am|revert)\b")


def basename(token):
    base = re.split(r"[\\/]", token)[-1]
    return base[:-4] if base.lower().endswith(".exe") else base


def normalise(cmd):
    """Turn unquoted newlines/backticks into ';', drop comments and line continuations, cut out heredoc bodies.

    Returns (text, heredoc_bodies). Bodies are only executed when fed to a shell, so the caller checks them then.
    """
    out, i, quote, n = [], 0, None, len(cmd)
    pending, bodies = [], []  # heredoc delimiters waiting for the end of the line
    while i < n:
        c = cmd[i]
        if quote == "'":
            out.append(c)
            if c == "'":
                quote = None
        elif quote == '"':
            if c == "\\" and i + 1 < n:
                out.append(c + cmd[i + 1])
                i += 1
            elif c == "`":
                out.append(";")
            else:
                out.append(c)
                if c == '"':
                    quote = None
        else:
            prev = cmd[i - 1] if i else " "
            if c == "\\" and i + 1 < n:
                if cmd[i + 1] == "\n":
                    i += 1  # line continuation
                else:
                    out.append(c + cmd[i + 1])
                    i += 1
            elif c in "'\"":
                quote = c
                out.append(c)
            elif c == "#" and (prev.isspace() or prev in ";&|()`"):
                while i < n and cmd[i] != "\n":  # comment runs to the end of the line
                    i += 1
                continue
            elif c == "<" and cmd.startswith("<<", i) and not cmd.startswith("<<<", i):
                j = i + 2
                strip_tabs = j < n and cmd[j] == "-"
                j += 1 if strip_tabs else 0
                while j < n and cmd[j] in " \t":
                    j += 1
                m = re.match(r"""'([^']*)'|"([^"]*)"|\\?([^\s;&|()<>]+)""", cmd[j:])
                if m:
                    pending.append(((m.group(1) or m.group(2) or m.group(3) or "").replace("\\", ""), strip_tabs))
                    out.append("<< ")
                    out.append(m.group(0).replace("\\", ""))
                    i = j + m.end()
                    continue
                out.append("<<")
                i += 2
                continue
            elif c in "\n`\r":
                out.append(";")
                if c == "\n" and pending:
                    i += 1
                    for delim, strip_tabs in pending:
                        start, body, found = i, [], False
                        while i < n:
                            end = cmd.find("\n", i)
                            line = cmd[i:] if end < 0 else cmd[i:end]
                            i = n if end < 0 else end + 1
                            if (line.lstrip("\t") if strip_tabs else line).rstrip("\r") == delim:
                                found = True
                                break
                            body.append(line)
                        if not found:  # not a heredoc after all (e.g. `$((1 << 2))`): parse the rest normally
                            i = start
                            break
                        bodies.append("\n".join(body))
                    pending = []
                    continue
            else:
                out.append(c)
        i += 1
    return "".join(out), bodies


def tokenize(text):
    lex = shlex.shlex(text, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)


def segments(tokens):
    """Split on operators; drop redirections (`>`, `2>&1`, `<<`) and their targets."""
    seg, drop_next = [], False
    for t in tokens:
        if t and set(t) <= OPERATORS:
            if seg:
                yield seg
            seg, drop_next = [], False
        elif drop_next:
            drop_next = False
        elif t and set(t) <= set("<>&") and ("<" in t or ">" in t):
            drop_next = True
        else:
            seg.append(t)
    if seg:
        yield seg


def real_flags(rest):
    """The argument tokens that are real options: not option values and not after `--`."""
    flags, skip = [], False
    for r in rest:
        if skip:
            skip = False
            continue
        if r == "--":
            break
        if r.startswith("-"):
            flags.append(r)
            skip = r in GIT_VALUE_OPTS
    return flags


def positionals(rest):
    out, skip = [], False
    for r in rest:
        if skip:
            skip = False
        elif r.startswith("-"):
            skip = r in GIT_VALUE_OPTS
        else:
            out.append(r)
    return out


def git_alias(name, cfg):
    """Expand a git alias from `-c alias.x=` options or the user's git config. None when it isn't one."""
    for c in cfg:
        if c.startswith("alias.%s=" % name):
            return c.split("=", 1)[1]
    try:
        r = subprocess.run(["git", "config", "--get", "alias." + name], capture_output=True, text=True, timeout=2,
                           env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))
        return r.stdout.strip() or None if r.returncode == 0 else None
    except Exception:
        return None


def git_risky(args, depth):
    i, cfg = 0, []
    while i < len(args):
        a = args[i]
        if a in GIT_OPTS_WITH_ARG:
            if a == "-c" and i + 1 < len(args):
                cfg.append(args[i + 1])
            i += 2
        elif a.startswith("-"):
            i += 1
        else:
            break
    sub = args[i] if i < len(args) else ""
    rest = args[i + 1:]
    flags = real_flags(rest)
    if sub in GIT_ALWAYS:
        if len(rest) == 1 and rest[0] in SOLE_SAFE_FLAGS:
            return False
        if sub in DRY_RUN_FLAGS and any(f in DRY_RUN_FLAGS[sub] for f in flags):
            return False
        if sub in NO_COMMIT_SUBS and "--no-commit" in flags:
            return False
        return True
    if sub == "tag":
        return bool(positionals(rest)) and not any(f in TAG_LIST_FLAGS for f in flags)
    if sub == "reset":
        if any(f in ("--hard", "--merge", "--keep", "--soft") for f in flags):
            return True
        before_dashdash = rest[:rest.index("--")] if "--" in rest else rest
        pos = positionals(before_dashdash)
        if len(pos) > 1 or ("--" in rest and rest[rest.index("--") + 1:]):
            return False  # `git reset <commit> -- <paths>` only unstages those paths; HEAD does not move
        return any(re.search(r"[~^]|^@\{|^ORIG_HEAD$|^FETCH_HEAD$|^[0-9a-f]{7,40}$", p) for p in pos)
    if sub == "stash":
        return not rest or rest[0] not in STASH_QUIET
    if sub == "branch":
        return any(f in ("-f", "--force", "-M", "-C", "-D") for f in flags)
    if sub == "checkout":
        return checkout_risky(rest, flags)
    if sub == "switch":
        return any(f in ("-C", "--force-create", "-f", "--force", "--discard-changes") for f in flags)
    if sub == "restore":
        if any(f in ("-h", "--help") for f in flags):
            return False
        staged = any(f in ("-S", "--staged") for f in flags)
        return not staged or any(f in ("-W", "--worktree") for f in flags)  # `--staged` alone only unstages
    if sub == "clean":
        return not any(f in ("-h", "--help", "--dry-run") or re.match(r"^-[A-Za-z]*n[A-Za-z]*$", f) for f in flags)
    if sub == "pull":
        return any(f in ("-r", "--rebase") or (f.startswith("--rebase=") and f != "--rebase=false") for f in flags)
    if sub == "svn":
        return bool(rest) and rest[0] in ("dcommit", "rebase", "commit-diff", "set-tree")
    if sub == "subtree":
        return any(p in SUBTREE_WRITE for p in positionals(rest)[:1]) or "--rejoin" in flags
    if sub == "submodule" and "foreach" in rest:
        inner = [r for r in rest[rest.index("foreach") + 1:] if r not in ("--recursive", "-q", "--quiet")]
        return depth < MAX_DEPTH and risky(" ".join(shlex.quote(r) for r in inner) if len(inner) > 1 else "".join(inner), depth + 1)
    if sub not in GIT_KNOWN and not sub.startswith("-") and depth < MAX_DEPTH:
        alias = git_alias(sub, cfg)
        if alias:
            tail = " ".join(shlex.quote(r) for r in rest)
            return risky(alias[1:] + " " + tail if alias.startswith("!") else "git " + alias + " " + tail, depth + 1)
    return False


def checkout_risky(rest, flags):
    """`-B`, `--force` and path checkouts (`git checkout -- f`, `git checkout .`, `git checkout HEAD f`) discard work."""
    if any(f in ("-B", "-f", "--force") for f in flags):
        return True
    if "--" in rest and rest[rest.index("--") + 1:]:
        return True
    pos, skip = [], False
    for r in (rest[:rest.index("--")] if "--" in rest else rest):
        if skip:
            skip = False
        elif r.startswith("-"):
            skip = r in ("-b", "-B", "--orphan")
        else:
            pos.append(r)
    return "." in pos or len(pos) > 1


def gh_risky(args):
    i = 0
    while i < len(args) and args[i].startswith("-"):
        i += 2 if args[i] in ("-R", "--repo", "--hostname") else 1
    rest = args[i:]
    if not rest:
        return False
    if rest[0] == "api":
        return gh_api_risky(rest[1:])
    if len(rest) >= 2 and rest[1] in GH_PAIRS.get(rest[0], ()):
        return not (len(rest) == 3 and rest[2] in ("--help", "-h"))
    return False


def gh_api_risky(args):
    """`gh api` writes when the method is a write verb, or — with no explicit method — when it sends a body (-f/-F/--input)."""
    if args and args[0] == "graphql":
        return gh_graphql_risky(args[1:])
    method, has_body = None, False
    for j, a in enumerate(args):
        if a in ("-X", "--method") and j + 1 < len(args):
            method = args[j + 1]
        elif a.startswith("--method="):
            method = a.split("=", 1)[1]
        elif a.startswith("-X") and len(a) > 2:
            method = a[2:]
        elif a in GH_BODY_FLAGS or a.startswith(("--field=", "--raw-field=", "--input=")) or re.match(r"^-[fF].", a):
            has_body = True
    if method is not None:
        return method.upper() in GH_WRITE_METHODS
    return has_body


def gh_graphql_risky(args):
    """`gh api graphql` always POSTs; it writes only when the query is a mutation (or comes from a file we cannot read)."""
    for j, a in enumerate(args):
        if a in GH_BODY_FLAGS and j + 1 < len(args):
            value = args[j + 1]
        elif a.startswith(("--field=", "--raw-field=", "--input=")):
            value = a.split("=", 1)[1]
        elif re.match(r"^-[fF].", a):
            value = a[2:]
        else:
            continue
        if a == "--input" or a.startswith("--input=") or GRAPHQL_MUTATION.search(value) \
                or value.split("=", 1)[-1].startswith("@"):
            return True
    return False


def js_risky(prog, args):
    pos, skip = [], False
    for a in args:
        if skip:
            skip = False
        elif a.startswith("-"):
            skip = a in JS_VALUE_OPTS
        else:
            pos.append(a)
    if not pos or any(a in ("-h", "--help") for a in args):
        return False
    if pos[0] in JS_PUBLISH:
        return True
    return prog == "yarn" and pos[:2] == ["npm", "publish"]


def gradle_risky(args):
    skip = False
    for a in args:
        if skip:
            skip = False
            continue
        if a.startswith("-"):
            skip = a in GRADLE_VALUE_OPTS
            continue
        task = a.rsplit(":", 1)[-1]
        if task.startswith("publish") and not task.endswith("MavenLocal"):
            return True
    return False


def maven_risky(args):
    """The `deploy` phase and any deploy/release plugin goal (`deploy:deploy-file`, `release:prepare`, full coordinates)."""
    skip = False
    for a in args:
        if skip:
            skip = False
            continue
        if a.startswith("-"):
            skip = a in MAVEN_VALUE_OPTS
            continue
        parts = a.split(":")
        if a == "deploy" or (len(parts) > 1 and any(p in MAVEN_PUBLISH_PLUGINS for p in parts[:-1])):
            return True
    return False


def command_start(seg):
    """Index of the real program in a segment, skipping keywords, env assignments and wrappers (with options)."""
    i = 0
    while i < len(seg) and (seg[i] in KEYWORDS or ENV_ASSIGN.match(seg[i])):
        i += 1
    if i < len(seg) and basename(seg[i]) in WRAPPERS:
        for j in range(i + 1, min(len(seg), i + 9)):
            if basename(seg[j]) in KNOWN_PROGS:
                return j
    return i


def risky(cmd, depth=0):
    BUDGET[0] -= 1
    if depth > MAX_DEPTH or BUDGET[0] < 0:
        return bool(FALLBACK_RE.search(cmd))
    cmd = IFS_RE.sub(" ", cmd)
    if SUBST_PROG.search(cmd):
        return True
    try:
        text, bodies = normalise(cmd)
        tokens = tokenize(text)
    except ValueError:  # unbalanced quotes etc. -> be conservative
        return bool(FALLBACK_RE.search(cmd))
    for seg in segments(tokens):
        i = command_start(seg)
        if i >= len(seg):
            continue
        prog = basename(seg[i])
        args = seg[i + 1:]
        if prog == "git" and git_risky(args, depth):
            return True
        if prog == "gh" and gh_risky(args):
            return True
        if prog in JS_PMS and js_risky(prog, args):
            return True
        if prog in MAVEN and maven_risky(args):
            return True
        if prog in GRADLE and gradle_risky(args):
            return True
        if (prog, args[0] if args else "") in OTHER_PUBLISH:
            return True
        if prog.startswith("$") and any(a in RISKY_WORDS for a in args[:3]):
            return True  # `$GIT push` — the program is a variable; assume the worst
        if prog in SHELLS:
            c_at = [j for j, a in enumerate(args) if re.match(r"^-[A-Za-z]*c[A-Za-z]*$", a)]
            if c_at:
                if any(risky(a, depth + 1) for a in args[c_at[0] + 1:] if not a.startswith(("-", "+"))):
                    return True
            elif not any(not a.startswith(("-", "+")) for a in args):
                # a shell reading stdin: `... | sh`, `bash <<EOF`. Check what may be piped or fed in.
                if any(risky(b, depth + 1) for b in bodies) or FALLBACK_RE.search(cmd):
                    return True
        if prog == "eval" and risky(" ".join(args), depth + 1):
            return True
        if prog in WRAPPERS:
            for j in range(i + 1, min(len(seg), i + 10)):
                if risky(" ".join(shlex.quote(a) for a in seg[j:]), depth + 1) or (j < len(seg) and " " in seg[j] and risky(seg[j], depth + 1)):
                    return True
    return False


def main():
    try:
        raw = sys.stdin.buffer.read().decode("utf-8", "replace")
        try:
            data = json.loads(raw)
            tool_input = data.get("tool_input") if isinstance(data, dict) else None
            cmd = tool_input.get("command", "") if isinstance(tool_input, dict) else ""
            if not isinstance(cmd, str):
                cmd = ""
        except ValueError:
            cmd = raw
        try:
            hit = risky(cmd)
        except Exception:  # never let a parser bug silently allow a commit
            hit = bool(FALLBACK_RE.search(cmd))
        if hit:
            print(json.dumps(ASK))
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())

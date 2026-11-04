#!/usr/bin/env python3
"""PreToolUse(Bash): ask before commits, pushes, tags, history rewrites and releases.

Policy (skill: completion-gate): never commit/push/tag/rebase/release until the developer asks.
Reads the tool-call JSON on stdin; prints a permissionDecision "ask" JSON when the command would
create a commit/tag, publish, or rewrite history. Parses the command (quotes, newlines, operators,
shell -c strings, wrappers, env prefixes) instead of grepping text, so quoted paths, multi-line
commands and chains are handled while `echo "git commit"` is not.

This is a best-effort safety net for Claude's Bash tool, not a security boundary: it cannot see
aliases, variable indirection, scripts that commit internally, or other tools. Always exits 0 —
a bug here must never block a developer's session.
"""
import json
import re
import shlex
import sys

ASK = {"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": ("ai-toolkit policy: do not commit, push, tag, release or rewrite history until "
                                 "the developer asks. Approve only if you asked for it."),
}}
OPERATORS = set(";&|()")
KEYWORDS = {"then", "do", "else", "elif", "if", "while", "until", "{", "}", "!", "time"}
WRAPPERS = {"sudo", "command", "env", "nohup", "exec", "builtin", "xargs", "nice", "ionice", "timeout", "stdbuf", "doas"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh", "fish"}
GIT_OPTS_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix", "--config-env"}
GIT_ALWAYS = {"commit", "push", "rebase", "cherry-pick", "merge", "am", "revert"}
SAFE_FLAGS = {"--abort", "--continue", "--skip", "--quit", "--dry-run", "--show-current-patch", "-h", "--help"}
PUSH_DRY_RUN_FLAGS = {"-n"}  # `-n` is --no-verify for commit and --no-stat for merge/rebase, so it is safe only for push
TAG_LIST_FLAGS = {"-l", "--list", "-n", "--contains", "--no-contains", "--merged", "--no-merged", "--points-at", "-v", "--verify"}
GH_WRITE_METHODS = {"POST", "PUT", "PATCH", "DELETE"}
GH_BODY_FLAGS = {"-f", "-F", "--field", "--raw-field", "--input"}
ENV_ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
SHELL_C = re.compile(r"^-[A-Za-z]*c[A-Za-z]*$")
PKG_PUBLISH = {("npm", "version"), ("npm", "publish"), ("yarn", "publish"), ("pnpm", "publish"), ("yarn", "version"), ("pnpm", "version")}


def basename(token):
    base = re.split(r"[\\/]", token)[-1]
    return base[:-4] if base.lower().endswith(".exe") else base


def normalise(cmd):
    """Turn unquoted newlines/backticks into ';' and drop backslash-newline continuations."""
    out, i, quote = [], 0, None
    while i < len(cmd):
        c = cmd[i]
        if quote == "'":
            out.append(c)
            if c == "'":
                quote = None
        elif quote == '"':
            if c == "\\" and i + 1 < len(cmd):
                out.append(c + cmd[i + 1])
                i += 1
            elif c == "`":
                out.append(";")
            else:
                out.append(c)
                if c == '"':
                    quote = None
        else:
            if c == "\\" and i + 1 < len(cmd):
                if cmd[i + 1] == "\n":
                    i += 1  # line continuation
                else:
                    out.append(c + cmd[i + 1])
                    i += 1
            elif c in "'\"":
                quote = c
                out.append(c)
            elif c in "\n`\r":
                out.append(";")
            else:
                out.append(c)
        i += 1
    return "".join(out)


def tokenize(cmd):
    lex = shlex.shlex(normalise(cmd), posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)


def segments(tokens):
    seg = []
    for t in tokens:
        if t and set(t) <= OPERATORS:
            if seg:
                yield seg
            seg = []
        else:
            seg.append(t)
    if seg:
        yield seg


def git_risky(args):
    i = 0
    while i < len(args):
        a = args[i]
        if a in GIT_OPTS_WITH_ARG:
            i += 2
        elif a.startswith("-"):
            i += 1
        else:
            break
    sub = args[i] if i < len(args) else ""
    rest = args[i + 1:]
    if sub in GIT_ALWAYS:
        safe = SAFE_FLAGS | PUSH_DRY_RUN_FLAGS if sub == "push" else SAFE_FLAGS
        return not any(r in safe or r == "--no-commit" for r in rest)
    if sub == "tag":
        has_name = any(not r.startswith("-") for r in rest)
        return has_name and not any(r in TAG_LIST_FLAGS for r in rest)
    if sub == "reset":
        return any(r in ("--hard", "--merge", "--keep") for r in rest)
    return False


def gh_risky(args):
    i = 0
    while i < len(args) and args[i].startswith("-"):
        i += 2 if args[i] in ("-R", "--repo", "--hostname") else 1
    rest = args[i:]
    if rest[:2] in (["pr", "create"], ["pr", "merge"], ["release", "create"]):
        return not any(r in ("--help", "-h") for r in rest)
    if rest[:1] == ["api"]:
        return gh_api_risky(rest[1:])
    return False


def gh_api_risky(args):
    """`gh api` writes when the method is a write verb, or — with no explicit method — when it sends a body (-f/-F/--input)."""
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


def command_start(seg):
    """Index of the real program in a segment, skipping keywords, env assignments and wrappers (with options)."""
    i = 0
    while i < len(seg) and (seg[i] in KEYWORDS or ENV_ASSIGN.match(seg[i])):
        i += 1
    if i < len(seg) and basename(seg[i]) in WRAPPERS:
        for j in range(i + 1, min(len(seg), i + 9)):
            if basename(seg[j]) in ("git", "gh", "npm", "yarn", "pnpm", "mvn", "mvnw") or basename(seg[j]) in SHELLS:
                return j
    return i


def risky(cmd, depth=0):
    try:
        tokens = tokenize(cmd)
    except ValueError:  # unbalanced quotes etc. -> be conservative
        return bool(re.search(r"(^|[\s;&|(`'\"])(git|gh)\b[^;&|]*\b(commit|push|tag|rebase|cherry-pick|merge|am|revert)\b", cmd))
    for seg in segments(tokens):
        i = command_start(seg)
        if i >= len(seg):
            continue
        prog = basename(seg[i])
        args = seg[i + 1:]
        if prog == "git" and git_risky(args):
            return True
        if prog == "gh" and gh_risky(args):
            return True
        if (prog, args[0] if args else "") in PKG_PUBLISH:
            return True
        if prog in ("mvn", "mvnw", "./mvnw") and any(a.startswith(("release:", "deploy")) or a == "deploy" for a in args):
            return True
        if depth < 4:
            if prog in SHELLS:
                for j, a in enumerate(args):
                    if SHELL_C.match(a) and j + 1 < len(args) and risky(args[j + 1], depth + 1):
                        return True
            if prog == "eval" and risky(" ".join(args), depth + 1):
                return True
            if prog in WRAPPERS and i + 1 < len(seg) and risky(" ".join(seg[i + 1:]), depth + 1):
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
            hit = bool(re.search(r"\bgit\b[^\n]*\b(commit|push)\b", cmd))
        if hit:
            print(json.dumps(ASK))
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Report relative markdown links that do not resolve to a file, or whose #anchor names no heading in it."""
import os, re, sys, glob
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINK = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)\s]+)\)")
bad = 0


def exists_exact_case(path):
    """True when every path component matches on disk with the same case (macOS is case-insensitive, Linux and GitHub are not)."""
    rel = os.path.relpath(path, ROOT)
    if rel.startswith(".."):
        return os.path.exists(path)
    cur = ROOT
    for part in rel.split(os.sep):
        if part not in os.listdir(cur):
            return False
        cur = os.path.join(cur, part)
    return True


def slug(heading):
    """GitHub's heading anchor: lower-case, drop punctuation except '-' and '_', spaces become '-'."""
    h = re.sub(r"`|\*\*|__", "", heading.strip().lower())
    h = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", h)
    h = re.sub(r"[^\w\- ]", "", h)
    return h.replace(" ", "-")


_anchors = {}
def anchors(path):
    if path not in _anchors:
        seen, out, fence = {}, set(), False
        for line in open(path, encoding="utf-8"):
            if line.lstrip().startswith(("```", "~~~")):
                fence = not fence
            m = None if fence else re.match(r"#{1,6}\s+(.*?)\s*#*\s*$", line)
            if m:
                s = slug(m.group(1))
                n = seen.get(s, 0)
                seen[s] = n + 1
                out.add(s if n == 0 else f"{s}-{n}")
            out.update(re.findall(r'<a\s+(?:name|id)="([^"]+)"', line))
        _anchors[path] = out
    return _anchors[path]


for path in glob.glob(os.path.join(ROOT, "**", "*.md"), recursive=True):
    if "/.git/" in path:
        continue
    in_code = False
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        if line.lstrip().startswith(("```", "~~~")):
            in_code = not in_code
        if in_code:
            continue
        for t in LINK.findall(line):
            if re.match(r"[a-z]+:|/", t) or "{{" in t:
                continue
            file_part, _, frag = t.partition("#")
            target = os.path.normpath(os.path.join(os.path.dirname(path), file_part)) if file_part else path
            if not exists_exact_case(target):
                bad += 1
                print(f"{os.path.relpath(path, ROOT)}:{n}: {t}")
            elif frag and target.endswith(".md") and os.path.isfile(target) and frag.lower() not in anchors(target):
                bad += 1
                print(f"{os.path.relpath(path, ROOT)}:{n}: {t}  (no heading for #{frag})")
print(f"{bad} broken link(s)")
sys.exit(1 if bad else 0)

#!/usr/bin/env python3
"""Report relative markdown links that do not resolve to a file."""
import os, re, sys, glob
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINK = re.compile(r"(?<!\!)\[[^\]]*\]\(([^)\s]+)\)")
bad = 0
for path in glob.glob(os.path.join(ROOT, "**", "*.md"), recursive=True):
    if "/.git/" in path or "/templates/" in path and path.endswith(".tmpl"):
        continue
    in_code = False
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        if line.lstrip().startswith("```"):
            in_code = not in_code
        if in_code:
            continue
        for t in LINK.findall(line):
            if re.match(r"[a-z]+:|#|/", t) or "{{" in t:
                continue
            target = os.path.normpath(os.path.join(os.path.dirname(path), t.split("#")[0]))
            if not os.path.exists(target):
                bad += 1
                print(f"{os.path.relpath(path, ROOT)}:{n}: {t}")
print(f"{bad} broken link(s)")
sys.exit(1 if bad else 0)

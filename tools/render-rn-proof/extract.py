#!/usr/bin/env python3
"""Render the code of the React Native skills into a freshly generated Expo app.

Called by tools/render-rn-proof.sh. Every config file, flow and shell step below is read out of a fenced block of a
SKILL.md or reference: nothing is retyped here, so a skill whose snippet is wrong or has drifted fails the render.

  extract.py render <repo-root> <app-dir>   write configs and flows into the app
  extract.py steps  <repo-root>             print the template-strip shell block
  extract.py drift  <repo-root> <app-dir>   report skill blocks that name a file but differ from the rendered one
"""
import glob
import json
import os
import re
import sys

FENCE = re.compile(r"^```([A-Za-z0-9_+-]*)[ \t]*\n(.*?)^```[ \t]*$", re.S | re.M)


def plugin_file(root, skill, rel="SKILL.md"):
    hits = glob.glob(os.path.join(root, "plugins", "*", "skills", skill, rel))
    if len(hits) != 1:
        sys.exit(f"extract: expected exactly one {skill}/{rel}, found {len(hits)}")
    return hits[0]


def fences(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    return [(m.group(1), m.group(2)) for m in FENCE.finditer(text)]


def block(path, first_line, lang=None):
    for found_lang, body in fences(path):
        if lang and found_lang != lang:
            continue
        if body.lstrip().startswith(first_line):
            return body
    sys.exit(f"extract: no ```{lang or ''} block starting with {first_line!r} in {os.path.relpath(path)}")


def strip_json_comments(text):
    return "\n".join(re.sub(r"(^|\s+)//.*$", "", line) if "//" in line else line for line in text.splitlines())


def write(app, rel, content):
    full = os.path.join(app, rel)
    os.makedirs(os.path.dirname(full) or ".", exist_ok=True)
    with open(full, "w", encoding="utf-8") as fh:
        fh.write(content if content.endswith("\n") else content + "\n")


def render(root, app):
    static = plugin_file(root, "react-native-static-analysis")
    unit = plugin_file(root, "react-native-unit-tests")
    e2e = plugin_file(root, "react-native-e2e-tests")
    structure = plugin_file(root, "react-native-code-structure")
    setup = plugin_file(root, "react-native-code-structure", "references/expo-template-setup.md")

    write(app, "eslint.config.mjs", block(static, "// eslint.config.mjs", "js"))
    write(app, ".prettierrc.json", block(static, '{ "singleQuote"', "json"))
    write(app, ".prettierignore", block(static, "coverage\ndist", ""))
    write(app, "jest.config.js", block(unit, "// jest.config.js", "js"))
    write(app, "babel.config.js", block(setup, "// babel.config.js", "js"))
    write(app, "jest.setup.ts", block(setup, "// jest.setup.ts", "ts"))

    hook = block(static, "# .husky/pre-commit", "sh")
    write(app, ".husky/pre-commit", "\n".join(hook.splitlines()[1:]))

    pkg_path = os.path.join(app, "package.json")
    with open(pkg_path, encoding="utf-8") as fh:
        pkg = json.load(fh)
    scripts = json.loads(block(static, '{ "scripts"', "json"))["scripts"]
    pkg["scripts"] = {k: v for k, v in pkg["scripts"].items() if k not in ("reset-project", "lint")}
    pkg["scripts"].update(scripts)
    pkg["lint-staged"] = json.loads(block(static, '{ "lint-staged"', "json"))["lint-staged"]
    write(app, "package.json", json.dumps(pkg, indent=2))

    ts = json.loads(strip_json_comments(block(structure, "// tsconfig.json", "json")))
    write(app, "tsconfig.json", json.dumps(ts, indent=2))

    flows = 0
    for lang, body in fences(e2e):
        if lang == "yaml" and body.startswith("# .maestro/"):
            header, rest = body.split("\n", 1)
            write(app, header[2:].split(":")[0].strip(), body)
            flows += 1
    if flows < 5:
        sys.exit(f"extract: expected at least 5 Maestro files in the e2e skill, found {flows}")
    print(f"rendered configs from skills; {flows} Maestro files")


def steps(root):
    setup = plugin_file(root, "react-native-code-structure", "references/expo-template-setup.md")
    print(block(setup, "rm -rf src/components", "sh").replace("\\\n", " "))


def normalise(code):
    code = re.sub(r"//[^\n]*", "", code)
    code = re.sub(r"/\*.*?\*/", "", code, flags=re.S)
    code = re.sub(r"[\s;'\"`(),]", "", code)
    return code


def drift(root, app):
    src = os.path.join(app, "src")
    rendered = {}
    for dirpath, _, names in os.walk(src):
        for name in names:
            full = os.path.join(dirpath, name)
            with open(full, encoding="utf-8") as fh:
                rendered[os.path.relpath(full, src)] = normalise(fh.read())
    checked = matched = 0
    misses = []
    for path in sorted(glob.glob(os.path.join(root, "plugins", "ai-toolkit-react-native-*", "skills", "*", "**", "*.md"), recursive=True)):
        for lang, body in fences(path):
            if lang not in ("ts", "tsx"):
                continue
            first = body.lstrip().splitlines()[0] if body.strip() else ""
            m = re.match(r"//\s*((?:src/)?[\w./\[\]@+-]+\.tsx?)\b", first)
            if not m:
                continue
            want = m.group(1).removeprefix("src/")
            target = next((r for r in rendered if r == want or r.endswith("/" + want)), None)
            if target is None:
                continue
            checked += 1
            chunk = normalise(body)
            if chunk and chunk in rendered[target]:
                matched += 1
            else:
                misses.append(f"{os.path.relpath(path, root)} -> src/{target}")
    print(f"drift: {matched}/{checked} skill blocks that name a source file appear verbatim (comments, quotes, commas and whitespace ignored) in the rendered app")
    for miss in misses:
        print(f"  differs: {miss}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "render" and len(sys.argv) == 4:
        render(sys.argv[2], sys.argv[3])
    elif cmd == "steps" and len(sys.argv) == 3:
        steps(sys.argv[2])
    elif cmd == "drift" and len(sys.argv) == 4:
        drift(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)

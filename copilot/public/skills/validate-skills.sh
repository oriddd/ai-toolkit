#!/usr/bin/env bash
# Structural validator for the skills catalogue.
# Exits non-zero on the first failure (CI-friendly).
#
# Usage:   bash validate-skills.sh
# Or:      ./validate-skills.sh   (after chmod +x)
#
# Optional: place a newline-separated list of forbidden substrings at
# `.publication-blocklist` (at the copilot/ root) to enable the
# publication-safety check. When the file is absent, that check is
# skipped. The file itself should not be committed if its terms are
# sensitive.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 0. Generated docs (REGISTRY.md, BACKEND_GUILD.md adoption matrix) must be in sync.
python3 "$ROOT/build-indexes.py" --check

python3 - "$ROOT" <<'PY'
import os, re, sys, glob

root = sys.argv[1]
errors = []
warnings = []

def err(msg):  errors.append(msg)
def warn(msg): warnings.append(msg)

def read(path):
    with open(path, encoding="utf-8") as h:
        return h.read()

# 1. Discover every SKILL.md under <name>/SKILL.md (skills are direct children)
all_skills = sorted(glob.glob(os.path.join(root, "*", "SKILL.md")))
if not all_skills:
    err("no skills found under */SKILL.md")

# 2. Per-skill frontmatter checks
FM_RE = re.compile(r"^---\n(.*?)\n---\n", re.S)
skill_meta = {}

for path in all_skills:
    rel       = os.path.relpath(path, root)
    folder    = os.path.basename(os.path.dirname(path))
    txt       = read(path)
    m         = FM_RE.match(txt)
    if not m:
        err(f"{rel}: missing YAML frontmatter (must start with `---` on line 1)")
        continue
    fm = m.group(1)
    name_m = re.search(r"^name:\s*(.+?)\s*$",   fm, re.M)
    desc_m = re.search(r"^description:\s*(.+)", fm, re.M)
    if not name_m: err(f"{rel}: frontmatter missing required `name:`")
    if not desc_m: err(f"{rel}: frontmatter missing required `description:`")
    name = name_m.group(1) if name_m else folder
    if name != folder:
        err(f"{rel}: frontmatter name `{name}` does not match folder `{folder}`")
    templates_dir = os.path.join(os.path.dirname(path), "templates")
    skill_meta[folder] = {
        "name": name,
        "has_templates": os.path.isdir(templates_dir),
        "templates_dir": templates_dir,
        "path": rel, "text": txt,
    }

# 3. Template references resolve
for folder, meta in skill_meta.items():
    if not meta["has_templates"]:
        if re.search(r"\]\(\./templates/", meta["text"]):
            err(f"{meta['path']}: links to `./templates/…` but the directory does not exist")
        continue
    if not os.listdir(meta["templates_dir"]):
        warn(f"{meta['path']}: `templates/` directory exists but is empty")
    for ref in set(re.findall(r"\]\(\./templates/([A-Za-z0-9._/-]+)\)", meta["text"])):
        full = os.path.join(meta["templates_dir"], ref)
        if not os.path.exists(full):
            err(f"{meta['path']}: links to `./templates/{ref}` but the file is missing")

# 4. Every skill indexed in README.md and in REGISTRY.md
index_readme = os.path.join(root, "README.md")
if not os.path.exists(index_readme):
    err("README.md (skills index) is missing")
else:
    body = read(index_readme)
    for folder in skill_meta:
        if folder not in body:
            err(f"README.md: missing entry for skill `{folder}`")

registry = os.path.join(root, "REGISTRY.md")
if os.path.exists(registry):
    reg_body = read(registry)
    for folder in skill_meta:
        if folder not in reg_body:
            err(f"REGISTRY.md: missing entry for skill `{folder}`")
else:
    warn("REGISTRY.md is missing (see AUTHORING.md)")

# 5. Forbidden placeholder syntaxes in templates/ files
FORBIDDEN = [
    (r"<basePackage(?:Path)?>",    "use {{basePackagePath}} / {{basePackage}} instead of <…>"),
    (r"__basePackage(?:Path)?__",  "use {{basePackagePath}} / {{basePackage}} instead of __…__"),
]
for tpl_path in glob.glob(os.path.join(root, "*", "templates", "**", "*"), recursive=True):
    if not os.path.isfile(tpl_path):
        continue
    try:
        body = read(tpl_path)
    except UnicodeDecodeError:
        continue
    rel = os.path.relpath(tpl_path, root)
    for pat, msg in FORBIDDEN:
        if re.search(pat, body):
            warn(f"{rel}: forbidden placeholder syntax — {msg}")

# 6. Publication safety — load blocklist from optional file next to the skills
blocklist_path = os.path.join(root, ".publication-blocklist")
blocklist = []
if os.path.exists(blocklist_path):
    for line in read(blocklist_path).splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            blocklist.append(line)

if blocklist:
    for path in glob.glob(os.path.join(root, "**", "*.md"), recursive=True):
        rel = os.path.relpath(path, root)
        with open(path, encoding="utf-8") as h:
            for i, line in enumerate(h, 1):
                for term in blocklist:
                    if term in line:
                        err(f"{rel}:{i}: publication-safety: blocklisted term {term!r} -> {line.strip()[:120]}")

# 7. Report
print(f"Validated {len(all_skills)} skill(s) in this catalogue.")
for w in warnings: print(f"  WARN  {w}")
for e in errors:   print(f"  ERR   {e}")

if errors:
    print(f"\nFAILED with {len(errors)} error(s), {len(warnings)} warning(s)."); sys.exit(1)
else:
    print(f"\nOK ({len(warnings)} warning(s))."); sys.exit(0)
PY


#!/usr/bin/env bash
# Structural validator for the skills catalogue.
# Exits non-zero on the first failure (CI-friendly).
#
# Usage:   bash skills/validate-skills.sh
# Or:      skills/validate-skills.sh   (after chmod +x)
#
# Optional: place a newline-separated list of forbidden substrings at
# `skills/.publication-blocklist` to enable the publication-safety
# check. When the file is absent, that check is skipped. The file
# itself should not be committed if its terms are sensitive.

set -euo pipefail

SKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 0. Generated docs (REGISTRY.md, BACKEND_GUILD.md adoption matrix) must be in sync.
python3 "$SKILLS_DIR/build-indexes.py" --check

python3 - "$SKILLS_DIR" <<'PY'
import os, re, sys, glob

skills_dir = sys.argv[1]
errors = []
warnings = []

def err(msg):  errors.append(msg)
def warn(msg): warnings.append(msg)

def read(path):
    with open(path, encoding="utf-8") as h:
        return h.read()

# 1. Discover every SKILL.md (tier-agnostic — any one-level subfolder works)
all_skills = sorted(glob.glob(os.path.join(skills_dir, "*", "*", "SKILL.md")))
if not all_skills:
    err("no skills found under skills/*/*/SKILL.md")

# 2. Per-skill frontmatter checks
FM_RE = re.compile(r"^---\n(.*?)\n---\n", re.S)
skill_meta = {}
folders_per_tier = {}

for path in all_skills:
    rel       = os.path.relpath(path, os.path.dirname(skills_dir))
    folder    = os.path.basename(os.path.dirname(path))
    tier_dir  = os.path.basename(os.path.dirname(os.path.dirname(path)))
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
        "tier_dir": tier_dir,
    }
    folders_per_tier.setdefault(tier_dir, []).append(folder)

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

# 4. Every skill indexed in its tier README + in REGISTRY.md
def check_index(readme_path, expected_folders, label):
    if not os.path.exists(readme_path):
        err(f"{label} README missing: {readme_path}")
        return
    body = read(readme_path)
    for folder in expected_folders:
        if folder not in body:
            err(f"{os.path.relpath(readme_path, os.path.dirname(skills_dir))}: missing entry for skill `{folder}`")

for tier_dir, folders in folders_per_tier.items():
    check_index(os.path.join(skills_dir, tier_dir, "README.md"), folders, tier_dir)

registry = os.path.join(skills_dir, "REGISTRY.md")
if os.path.exists(registry):
    reg_body = read(registry)
    for folder in skill_meta:
        if folder not in reg_body:
            err(f"REGISTRY.md: missing entry for skill `{folder}`")
else:
    warn("REGISTRY.md is missing (see skills/AUTHORING.md)")

# 5. Forbidden placeholder syntaxes in templates/ files
FORBIDDEN = [
    (r"<basePackage(?:Path)?>",    "use {{basePackagePath}} / {{basePackage}} instead of <…>"),
    (r"__basePackage(?:Path)?__",  "use {{basePackagePath}} / {{basePackage}} instead of __…__"),
]
for tpl_path in glob.glob(os.path.join(skills_dir, "*", "*", "templates", "**", "*"), recursive=True):
    if not os.path.isfile(tpl_path):
        continue
    try:
        body = read(tpl_path)
    except UnicodeDecodeError:
        continue
    rel = os.path.relpath(tpl_path, os.path.dirname(skills_dir))
    for pat, msg in FORBIDDEN:
        if re.search(pat, body):
            warn(f"{rel}: forbidden placeholder syntax — {msg}")

# 6. Publication safety — load blocklist from optional file
blocklist_path = os.path.join(skills_dir, ".publication-blocklist")
blocklist = []
if os.path.exists(blocklist_path):
    for line in read(blocklist_path).splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            blocklist.append(line)

if blocklist:
    for path in glob.glob(os.path.join(skills_dir, "**", "*.md"), recursive=True):
        rel = os.path.relpath(path, os.path.dirname(skills_dir))
        with open(path, encoding="utf-8") as h:
            for i, line in enumerate(h, 1):
                for term in blocklist:
                    if term in line:
                        err(f"{rel}:{i}: publication-safety: blocklisted term {term!r} → {line.strip()[:120]}")

# 7. Report
print(f"Validated {len(all_skills)} skill(s) across {len(folders_per_tier)} tier(s): "
      + ", ".join(f"{t}={len(f)}" for t, f in sorted(folders_per_tier.items())))
for w in warnings: print(f"  WARN  {w}")
for e in errors:   print(f"  ERR   {e}")

if errors:
    print(f"\nFAILED with {len(errors)} error(s), {len(warnings)} warning(s)."); sys.exit(1)
else:
    print(f"\nOK ({len(warnings)} warning(s))."); sys.exit(0)
PY

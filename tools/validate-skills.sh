#!/usr/bin/env bash
# Structural validator for the skills catalogue.
# Exits non-zero on the first failure (CI-friendly).
#
# Usage:   bash validate-skills.sh
# Or:      ./validate-skills.sh   (after chmod +x)
#
# Optional: place a newline-separated list of forbidden substrings at
# `.publication-blocklist` (at the repo root) to enable the
# publication-safety check. When the file is absent, that check is
# skipped. The file itself should not be committed if its terms are
# sensitive.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 0. Generated docs (REGISTRY.md, BACKEND_GUILD.md adoption matrix) must be in sync.
docs_stale=0
python3 "$ROOT/tools/build-indexes.py" --check || docs_stale=1

DOCS_STALE="$docs_stale" python3 - "$ROOT" <<'PY'
import os, re, sys, glob

root = sys.argv[1]
errors = []
warnings = []

def err(msg):  errors.append(msg)
def warn(msg): warnings.append(msg)

def read(path):
    with open(path, encoding="utf-8") as h:
        return h.read()

if os.environ.get("DOCS_STALE") == "1":
    err("generated docs are out of date — run: python3 tools/build-indexes.py")

# 1. Discover every SKILL.md under <name>/SKILL.md (skills are direct children)
all_skills = sorted(glob.glob(os.path.join(root, "plugins", "*", "skills", "*", "SKILL.md")))
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
    desc_block = fm[desc_m.start():] if desc_m else ""
    if desc_m and not re.search(r"\b(use|apply)\s+(this skill\s+)?(when|whenever|before|during|only|as|for)\b|\bto apply\b", desc_block, re.I):
        err(f"{rel}: description must say WHEN to use the skill (`Use when …` / `Apply when …`) so agents route to it")
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
index_readme = os.path.join(root, "docs", "README.md")
if not os.path.exists(index_readme):
    err("README.md (skills index) is missing")
else:
    body = read(index_readme)
    for folder in skill_meta:
        if folder not in body:
            err(f"README.md: missing entry for skill `{folder}`")

registry = os.path.join(root, "docs", "REGISTRY.md")
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
for tpl_path in glob.glob(os.path.join(root, "plugins", "*", "skills", "*", "templates", "**", "*"), recursive=True):
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
    for path in glob.glob(os.path.join(root, "docs", "**", "*.md"), recursive=True) + glob.glob(os.path.join(root, "plugins", "**", "*.md"), recursive=True):
        rel = os.path.relpath(path, root)
        with open(path, encoding="utf-8") as h:
            for i, line in enumerate(h, 1):
                for term in blocklist:
                    if term in line:
                        err(f"{rel}:{i}: publication-safety: blocklisted term {term!r} -> {line.strip()[:120]}")

# 6b. Marketplace integrity: manifests, plugin membership, no cross-plugin links
import json
mp_path = os.path.join(root, ".claude-plugin", "marketplace.json")
if not os.path.exists(mp_path):
    err(".claude-plugin/marketplace.json is missing")
else:
    mp = json.loads(read(mp_path))
    listed = {}
    for pl in mp.get("plugins", []):
        listed[pl["name"]] = os.path.normpath(os.path.join(root, pl["source"]))
    for pname, pdir in listed.items():
        manifest = os.path.join(pdir, ".claude-plugin", "plugin.json")
        if not os.path.exists(manifest):
            err(f"{pname}: missing .claude-plugin/plugin.json"); continue
        pj = json.loads(read(manifest))
        if pj.get("name") != pname:
            err(f"{pname}: plugin.json name `{pj.get('name')}` does not match marketplace entry")
        for key in ("description", "version"):
            if not pj.get(key): err(f"{pname}: plugin.json missing `{key}`")
    on_disk = {d for d in os.listdir(os.path.join(root, "plugins")) if os.path.isdir(os.path.join(root, "plugins", d))}
    for d in sorted(on_disk - {os.path.basename(x) for x in listed.values()}):
        err(f"plugins/{d}: not listed in marketplace.json")

    # Language contract: every complete/draft language provides the required concerns
    REQUIRED = {"design": ["code-structure"], "build": ["input-validation"], "quality": ["unit-tests", "static-analysis"], "ops": ["ci"]}
    langs = {}
    for pname in listed:
        mm = re.match(r"ai-toolkit-(.+)-(design|build|quality|ops)$", pname)
        if mm: langs.setdefault(mm.group(1), {})[mm.group(2)] = pname
    for lang, phases in sorted(langs.items()):
        slug = "" if lang == "java" else lang + "-"
        for phase, needs in REQUIRED.items():
            if phase not in phases:
                err(f"language `{lang}`: missing plugin ai-toolkit-{lang}-{phase}"); continue
            have = {os.path.basename(os.path.dirname(x)) for x in glob.glob(os.path.join(listed[phases[phase]], "skills", "*", "SKILL.md"))}
            for need in needs:
                if slug + need not in have:
                    err(f"language `{lang}`: {phases[phase]} must provide `{slug}{need}` (docs/LANGUAGE_CONTRACT.md)")
        if "build" in phases:
            have = {os.path.basename(os.path.dirname(x)) for x in glob.glob(os.path.join(listed[phases["build"]], "skills", "*", "SKILL.md"))}
            if not ({slug + "error-handling", slug + "exception-handling"} & have):
                err(f"language `{lang}`: build plugin must provide `{slug}error-handling` (or `exception-handling` for Java)")
        hook = os.path.join(listed.get(phases.get("design", ""), root), "hooks", "detect-and-route.sh")
        if "design" in phases and not os.access(hook, os.X_OK):
            err(f"language `{lang}`: design plugin needs an executable hooks/detect-and-route.sh")
    seen = {}
    for path in all_skills:
        pname = path.split(os.sep)[-4]; skill = path.split(os.sep)[-2]
        if skill in seen: err(f"skill `{skill}` exists in both {seen[skill]} and {pname}")
        seen[skill] = pname
    for path in all_skills:
        pname = path.split(os.sep)[-4]
        for m in re.finditer(r"\]\(\.\./([a-z0-9-]+)/SKILL\.md", read(path)):
            if seen.get(m.group(1)) != pname:
                err(f"{os.path.relpath(path, root)}: link to `{m.group(1)}` crosses plugin boundary — reference it by name instead")
    # Plugin dependencies: every cross-plugin `depends_on` must be covered by a (transitive) plugin dependency; no cycles
    pdeps = {}
    for pname, pdir in listed.items():
        mf = os.path.join(pdir, ".claude-plugin", "plugin.json")
        pdeps[pname] = json.loads(read(mf)).get("dependencies", []) if os.path.exists(mf) else []
        for d in pdeps[pname]:
            if d not in listed: err(f"{pname}: dependency `{d}` is not a plugin in this marketplace")
    def _closure(p, acc=None):
        acc = set() if acc is None else acc
        for d in pdeps.get(p, []):
            if d not in acc:
                acc.add(d); _closure(d, acc)
        return acc
    for p in pdeps:
        if p in _closure(p): err(f"{p}: plugin dependencies form a cycle")
    for path in all_skills:
        pname = path.split(os.sep)[-4]
        dm = re.search(r"^depends_on:\s*\[(.*?)\]", read(path), re.M)
        for dep in [x.strip() for x in (dm.group(1).split(",") if dm else []) if x.strip()]:
            owner = seen.get(dep)
            if owner and owner != pname and owner not in _closure(pname):
                err(f"{os.path.relpath(path, root)}: depends_on `{dep}` lives in {owner}, which {pname} does not depend on (add it to plugin.json dependencies)")
    agent_names = {os.path.basename(a)[:-3] for a in glob.glob(os.path.join(root, "plugins", "*", "agents", "*.md"))}
    for agent in glob.glob(os.path.join(root, "plugins", "*", "agents", "*.md")):
        rel = os.path.relpath(agent, root)
        body = read(agent)
        fmm = FM_RE.match(body)
        if fmm and re.search(r"^description:\s*(\S+)\s*$", fmm.group(1), re.M) and re.search(r"^description:\s*" + re.escape(os.path.basename(agent)[:-3]) + r"\s*$", fmm.group(1), re.M):
            err(f"{rel}: description just repeats the agent name — say what it does and when to use it")
        if not re.search(r"(^|-)(code-review|update-context|test-writer)$", os.path.basename(agent)[:-3]) and "completion-gate" not in body:
            err(f"{rel}: code-writing agent must run the `completion-gate` skill and must not commit")
        for sub in re.findall(r"`((?:[a-z-]+-)?(?:test-writer|code-review)|update-context)`", body):
            if sub not in agent_names: err(f"{rel}: delegates to unknown agent `{sub}`")
        for sk in re.findall(r"`(parallel-delegation)`", body):
            if sk not in seen: err(f"{rel}: references unknown skill `{sk}`")
    for agent in glob.glob(os.path.join(root, "plugins", "*", "agents", "*.md")):
        fm = FM_RE.match(read(agent))
        rel = os.path.relpath(agent, root)
        if not fm or "name:" not in fm.group(1) or "description:" not in fm.group(1):
            err(f"{rel}: agent needs `name:` and `description:` frontmatter")
        for m in re.finditer(r"\]\(\.\./skills/", read(agent)):
            err(f"{rel}: relative link into skills/ breaks when plugins install separately — reference skills by name")
            break

# 6c. Plugin integrity: agent names, links that escape a plugin, hooks, routing tables, skill folders
agents_all = glob.glob(os.path.join(root, "plugins", "*", "agents", "*.md"))
for agent in agents_all:
    fmm = FM_RE.match(read(agent))
    if fmm:
        nm = re.search(r"^name:\s*(\S+)\s*$", fmm.group(1), re.M)
        if nm and nm.group(1) != os.path.basename(agent)[:-3]:
            err(f"{os.path.relpath(agent, root)}: agent name `{nm.group(1)}` does not match file name")

for skill_dir in glob.glob(os.path.join(root, "plugins", "*", "skills", "*")):
    if os.path.isdir(skill_dir) and not os.path.exists(os.path.join(skill_dir, "SKILL.md")):
        err(f"{os.path.relpath(skill_dir, root)}: skill folder without SKILL.md")

LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\((\.{1,2}/[^)\s#]*)")
for md in glob.glob(os.path.join(root, "plugins", "**", "*.md"), recursive=True):
    plugin_dir = os.path.join(root, "plugins", os.path.relpath(md, os.path.join(root, "plugins")).split(os.sep)[0])
    in_code = False
    for n, line in enumerate(read(md).split("\n"), 1):
        if line.lstrip().startswith("```"):
            in_code = not in_code
        if in_code:
            continue
        for target in LINK_RE.findall(line):
            resolved = os.path.normpath(os.path.join(os.path.dirname(md), target))
            if not resolved.startswith(plugin_dir + os.sep):
                err(f"{os.path.relpath(md, root)}:{n}: relative link `{target}` leaves its plugin — plugins install separately; reference by name")

known_names = set(seen) | {os.path.basename(a)[:-3] for a in agents_all}
for hooks_dir in glob.glob(os.path.join(root, "plugins", "*", "hooks")):
    rel = os.path.relpath(hooks_dir, root)
    for script in glob.glob(os.path.join(hooks_dir, "*.sh")) + glob.glob(os.path.join(hooks_dir, "*.py")):
        if not os.access(script, os.X_OK):
            err(f"{os.path.relpath(script, root)}: hook script must be executable")
    hj = os.path.join(hooks_dir, "hooks.json")
    if not os.path.exists(hj):
        err(f"{rel}: hooks/ without hooks.json"); continue
    try:
        cfg = json.loads(read(hj))
    except ValueError as e:
        err(f"{os.path.relpath(hj, root)}: invalid JSON ({e})"); continue
    for event, groups in cfg.get("hooks", {}).items():
        for grp in groups:
            for h in grp.get("hooks", []):
                cmd = h.get("command", "")
                m = re.search(r"\$\{CLAUDE_PLUGIN_ROOT\}/(hooks/[A-Za-z0-9_.-]+)", cmd)
                if m and not os.path.exists(os.path.join(hooks_dir, "..", m.group(1))):
                    err(f"{os.path.relpath(hj, root)}: {event} hook runs missing file {m.group(1)}")
    routing = os.path.join(hooks_dir, "routing.md")
    if os.path.exists(routing):
        text = read(routing)
        if len(text.split()) > 400:
            err(f"{os.path.relpath(routing, root)}: routing table is {len(text.split())} words (limit 400) — it is injected every session")
        phase_letter = {"d": "design", "b": "build", "q": "quality", "o": "ops"}
        for line in text.split("\n"):
            if line.startswith("|") and not line.startswith("| ---") and not line.startswith("| Task") and not line.startswith("| Situation"):
                last = line.strip().strip("|").split("|")[-1]
                for pref, tok, qual in re.findall(r"`(?:(ai-toolkit-[a-z-]+):)?([a-z0-9-]+)`(?: \(([a-z0-9-]+)\))?", last):
                    if tok not in known_names:
                        err(f"{os.path.relpath(routing, root)}: routes to unknown skill `{tok}`")
                    elif pref and tok in seen and seen[tok] != pref:
                        err(f"{os.path.relpath(routing, root)}: `{pref}:{tok}` — `{tok}` lives in {seen[tok]}")
                    elif tok in seen and qual:
                        want = qual if qual.startswith("ai-toolkit-") else None
                        if qual in phase_letter:
                            lang_plugin = os.path.basename(os.path.dirname(hooks_dir))  # e.g. ai-toolkit-java-design
                            want = lang_plugin.rsplit("-", 1)[0] + "-" + phase_letter[qual]
                        if want and seen[tok] != want:
                            err(f"{os.path.relpath(routing, root)}: `{tok}` is routed as ({qual}) but lives in {seen[tok]}")

# 6d. Catalogue quality: depends_on, tiers, description size/markers, reachability, agent coverage, contract details
import importlib.util
_spec = importlib.util.spec_from_file_location("build_indexes", os.path.join(root, "tools", "build-indexes.py"))
_bi = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_bi)
skill_fm = {}
for path in all_skills:
    skill_fm[path.split(os.sep)[-2]] = (path, _bi.parse_fm(read(path)))
agent_fm = {}
for agent in agents_all:
    agent_fm[os.path.basename(agent)[:-3]] = (agent, _bi.parse_fm(read(agent)))
BUILTIN_NAMES = {"init", "review", "security-review", "simplify", "loop", "schedule", "run", "fewer-permission-prompts",
                 "update-config", "keybindings-help", "claude-api", "dataviz", "code-review", "statusline-setup", "explore",
                 "plan", "general-purpose", "claude-code-guide", "fork", "claude", "help", "clear", "compact", "config",
                 "permissions", "doctor", "memory", "model", "login", "logout", "agents", "mcp", "hooks", "cost", "status"}
# `permissions` is an original skill name; plugin skills are namespaced (plugin:skill), so the built-in /permissions is not shadowed.
BUILTIN_OVERLAP_OK = {"permissions"}
VALID_TIERS = {"must", "should", "may", "foundational"}
LANG_MARKER = {"python": ("python",), "react-native": ("react native",), "java": ("java", "spring", "maven")}
for name, (path, fm) in sorted(skill_fm.items()):
    rel = os.path.relpath(path, root)
    pdir = path.split(os.sep)[-4]
    if fm.get("tier") not in VALID_TIERS:
        err(f"{rel}: tier `{fm.get('tier')}` must be one of {sorted(VALID_TIERS)}")
    for dep in fm.get("depends_on", []) if isinstance(fm.get("depends_on", []), list) else []:
        if dep not in skill_fm:
            err(f"{rel}: depends_on names unknown skill `{dep}`")
    desc = fm.get("description", "")
    if len(desc) > 600:
        err(f"{rel}: description is {len(desc)} chars (limit 600) — the skill listing is budgeted, long descriptions get truncated")
    if name.lower() in BUILTIN_NAMES and name not in BUILTIN_OVERLAP_OK:
        err(f"{rel}: skill name `{name}` collides with a Claude Code built-in")
    for lang, markers in LANG_MARKER.items():
        in_lang_plugin = ("-" + lang + "-") in pdir
        if in_lang_plugin and not any(m in desc.lower() for m in markers):
            err(f"{rel}: description of a {lang} skill must name its language ({'/'.join(markers)}) so it does not mis-route in other stacks")
for name, (path, fm) in sorted(agent_fm.items()):
    if name.lower() in BUILTIN_NAMES and not name.startswith(("ai-toolkit",)):
        pass  # bare agent names are plugin-namespaced at runtime; collisions are documented, not an error
agent_names_list = [os.path.basename(a)[:-3] for a in agents_all]
for n in {x for x in agent_names_list if agent_names_list.count(x) > 1}:
    err(f"agent name `{n}` exists in more than one plugin")

# size: a skill body is loaded in full on every invocation — deep dives belong in references/ (docs/AUTHORING.md §3b)
MAX_SKILL_BYTES = 16 * 1024
for name, (path, fm) in sorted(skill_fm.items()):
    size = len(read(path).encode("utf-8"))
    if size > MAX_SKILL_BYTES:
        err(f"{os.path.relpath(path, root)}: SKILL.md is {size} bytes (limit {MAX_SKILL_BYTES}) — move deep-dive sections to references/")

# agents: reviewers are read-only by construction; implementers deliberately inherit all tools (they edit files and run builds)
for name, (path, fm) in sorted(agent_fm.items()):
    if name.endswith("code-review") or name.endswith("-review"):
        tools = str(fm.get("tools", ""))
        rel = os.path.relpath(path, root)
        if not tools:
            err(f"{rel}: review agents must declare `tools` (read-only) instead of inheriting every tool")
        elif re.search(r"\b(Write|Edit|NotebookEdit)\b", tools):
            err(f"{rel}: review agents must not have write tools (found: {tools})")

# citations: `skill` §N must resolve to a heading in that skill's SKILL.md or references/
_heads = {}
for name, (path, fm) in skill_fm.items():
    hs = []
    for f in [path] + sorted(glob.glob(os.path.join(os.path.dirname(path), "references", "*.md"))):
        fence = False
        for line in read(f).split("\n"):
            if line.startswith("```"):
                fence = not fence
            if not fence and re.match(r"#{2,4} ", line):
                hs.append(line)
    _heads[name] = hs
_cite = re.compile(r"`([a-z][a-z0-9-]+)`\s*(?:skill\s*)?§\s?([0-9]+[a-z]?)")
for f in (glob.glob(os.path.join(root, "docs", "**", "*.md"), recursive=True)
          + glob.glob(os.path.join(root, "plugins", "*", "agents", "*.md"))
          + glob.glob(os.path.join(root, "plugins", "*", "skills", "*", "**", "*.md"), recursive=True)):
    for n, line in enumerate(read(f).split("\n"), 1):
        for target, sec in _cite.findall(line):
            if target in _heads and not any(re.match(r"#{2,4} " + sec + r"(?![0-9a-z])", h) for h in _heads[target]):
                err(f"{os.path.relpath(f, root)}:{n}: cites `{target}` §{sec}, which has no such heading")

# reachability: every skill must be routed, referenced by another skill/agent/routing table, or depended on
corpus = {}
for p in all_skills + agents_all + glob.glob(os.path.join(root, "plugins", "*", "hooks", "routing.md")):
    corpus[p] = read(p)
for name in sorted(skill_fm):
    own = skill_fm[name][0]
    pat = re.compile(r"`(?:ai-toolkit-[a-z-]+:)?" + re.escape(name) + r"`")
    if not any(p != own and pat.search(t) for p, t in corpus.items()):
        err(f"skill `{name}` is unreachable: no routing table, agent or other skill references it")

# docs coverage (word-boundary, not substring): skill in docs/INDEX_BY_USE_CASE.md; every agent in docs/agents/README.md
idx = os.path.join(root, "docs", "INDEX_BY_USE_CASE.md")
if os.path.exists(idx):
    idx_text = read(idx)
    for name in sorted(skill_fm):
        if not re.search(r"`" + re.escape(name) + r"`", idx_text):
            err(f"docs/INDEX_BY_USE_CASE.md: no entry for skill `{name}`")
ag_readme = os.path.join(root, "docs", "agents", "README.md")
if os.path.exists(ag_readme):
    ag_text = read(ag_readme)
    for name in sorted(agent_fm):
        if not re.search(r"`" + re.escape(name) + r"`", ag_text) and not re.search(re.escape(name) + r"\.md", ag_text):
            err(f"docs/agents/README.md: no entry for agent `{name}`")
if os.path.exists(os.path.join(root, "docs", "README.md")):
    rd = read(os.path.join(root, "docs", "README.md"))
    for name in sorted(skill_fm):
        if not re.search(r"`" + re.escape(name) + r"`", rd):
            err(f"docs/README.md: no entry for skill `{name}` (word-boundary check)")

# language contract extras: agents plugin needs code-review + test-writer; completion-gate has a row per language
gate = os.path.join(root, "plugins", "ai-toolkit-quality", "skills", "completion-gate", "SKILL.md")
for lang, label in (("java", "Java"), ("python", "Python"), ("react-native", "React Native")):
    pname = f"ai-toolkit-{lang}-agents"
    if os.path.isdir(os.path.join(root, "plugins", pname)):
        slug = "" if lang == "java" else lang + "-"
        for need in (slug + "code-review", slug + "test-writer"):
            if need not in agent_fm:
                err(f"{pname}: language contract requires agent `{need}`")
    if os.path.exists(gate) and ("| " + label) not in read(gate):
        err(f"completion-gate/SKILL.md: missing a command row for {label} (docs/LANGUAGE_CONTRACT.md)")

# manifests: semver version, no version duplicated in the marketplace entry
for pl in mp.get("plugins", []):
    if "version" in pl:
        err(f"marketplace.json: entry `{pl['name']}` must not set `version` (plugin.json owns it)")
for pname, pdir in listed.items():
    try:
        pj = json.loads(read(os.path.join(pdir, ".claude-plugin", "plugin.json")))
    except (OSError, ValueError):
        continue
    if not re.match(r"^\d+\.\d+\.\d+$", str(pj.get("version", ""))):
        err(f"{pname}: plugin.json version `{pj.get('version')}` is not MAJOR.MINOR.PATCH")
    for dep in pj.get("dependencies", []):
        dn = dep if isinstance(dep, str) else dep.get("name")
        if dn not in listed:
            err(f"{pname}: dependency `{dn}` is not a plugin of this marketplace")

# 6e. Strict YAML: frontmatter must parse with a strict parser (tolerant readers hide bugs such as an unquoted ': ')
try:
    import yaml as _yaml
except ImportError:
    _yaml = None
    warn("PyYAML not installed — strict frontmatter parsing skipped (pip install pyyaml; CI enforces it)")
if _yaml:
    for _p in list(all_skills) + list(agents_all):
        _m = FM_RE.match(read(_p))
        if not _m:
            continue
        try:
            _yaml.safe_load(_m.group(1))
        except Exception as _e:
            err(f"{os.path.relpath(_p, root)}: frontmatter is not valid YAML ({str(_e).splitlines()[0][:90]})")

# 6f. Single source of truth for the per-language verify commands: wherever they are quoted they must be identical
CANON_RN = "tsc --noEmit && eslint . --max-warnings 0 && prettier --check . && jest --ci --coverage"
CANON_PY = 'uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run lint-imports && uv run pytest -m "not integration"'
for p in glob.glob(os.path.join(root, "plugins", "**", "*.md"), recursive=True) + glob.glob(os.path.join(root, "docs", "**", "*.md"), recursive=True):
    t = read(p)
    if "tsc --noEmit &&" in t and CANON_RN not in t:
        err(f"{os.path.relpath(p, root)}: quotes a React Native verify script that differs from the canonical `{CANON_RN}`")
for rel in ("plugins/ai-toolkit-python-ops/skills/python-ci/SKILL.md", "plugins/ai-toolkit-python-quality/skills/python-static-analysis/SKILL.md",
            "plugins/ai-toolkit-quality/skills/completion-gate/SKILL.md"):
    pth = os.path.join(root, rel)
    if os.path.exists(pth) and CANON_PY not in read(pth):
        err(f"{rel}: must contain the canonical Python verify sequence `{CANON_PY}`")

# 7. Report
print(f"Validated {len(all_skills)} skill(s) in this catalogue.")
for w in warnings: print(f"  WARN  {w}")
for e in errors:   print(f"  ERR   {e}")

if errors:
    print(f"\nFAILED with {len(errors)} error(s), {len(warnings)} warning(s)."); sys.exit(1)
else:
    print(f"\nOK ({len(warnings)} warning(s))."); sys.exit(0)
PY


#!/usr/bin/env python3
"""Generate the `claude plugin eval` suites under evals/<plugin>/ from tools/eval_cases/.

Usage:  python3 tools/build-evals.py           # (re)write every case
        python3 tools/build-evals.py --check   # exit 1 when evals/ is out of date
"""
import filecmp
import glob
import json
import os
import shutil
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from eval_cases.agents import AGENT_SKILLS, AGENTS, FIXTURES, NO_DELEGATE, UNRELATED_AGENT_PROMPT  # noqa: E402
from eval_cases.behaviour import BEHAVIOUR  # noqa: E402
from eval_cases.triggers import OTHER_STACK, TRIGGERS, UNRELATED  # noqa: E402

LANGS = ("react-native", "react-web", "python", "java")


def closure(plugin):
    seen, todo = [], [plugin]
    while todo:
        p = todo.pop(0)
        if p in seen:
            continue
        seen.append(p)
        with open(os.path.join(ROOT, "plugins", p, ".claude-plugin", "plugin.json"), encoding="utf-8") as h:
            todo += json.load(h).get("dependencies", [])
    return seen


def plugins_line(plugin):
    return "plugins: [" + ", ".join(f'"../../../plugins/{p}"' for p in closure(plugin)) + "]\n"


def skill_re(names):
    return '"skill"\\s*:\\s*"(?:[\\w-]+:)?(' + "|".join(sorted(names)) + ')"'


def agent_re(names):
    return '"subagent_type"\\s*:\\s*"(?:[\\w-]+:)?(' + "|".join(sorted(names)) + ')"'


def subagent_skill_re(skills):
    s = '"skill":"(?:[\\w-]+:)?(' + "|".join(skills) + ')"'
    sub = '"parent_tool_use_id":"[^"]+"'
    return sub + "[^\\n]*" + s + "|" + s + "[^\\n]*" + sub


def generate(out):
    def write(path, text, mode=None):
        path = os.path.join(out, path)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as h:
            h.write(text)
        if mode:
            os.chmod(path, mode)

    plugins = {}
    for p in sorted(glob.glob(os.path.join(ROOT, "plugins", "*", "skills", "*", "SKILL.md"))):
        parts = p.split(os.sep)
        plugins.setdefault(parts[-4], []).append(parts[-2])
    missing = sorted(s for ss in plugins.values() for s in ss if s not in TRIGGERS)
    if missing:
        sys.exit(f"tools/eval_cases/triggers.py has no trigger prompt for: {', '.join(missing)}")

    for plugin, skills in plugins.items():
        for s in skills:
            write(f"{plugin}/trigger-{s}/prompt.md",
                  f"---\ndescription: \"`{s}` loads for a typical request, routed by its description alone\"\n"
                  f"tags: [trigger]\n{plugins_line(plugin)}max_turns: 4\nallowed_tools: [Skill, Read, Glob, Grep]\n---\n\n{TRIGGERS[s]}\n")
            write(f"{plugin}/trigger-{s}/graders/skill-loaded.md",
                  f"---\ntype: tool_used\ntool: Skill\ninput_match: '{skill_re([s])}'\n---\n")
        negatives = [("no-trigger-unrelated", UNRELATED, "an unrelated question")]
        lang = next((l for l in LANGS if plugin.startswith(f"ai-toolkit-{l}-")), None)
        if lang:
            negatives.append(("no-trigger-other-stack", OTHER_STACK[lang], "a request for a different language stack"))
        for name, prompt, what in negatives:
            write(f"{plugin}/{name}/prompt.md",
                  f"---\ndescription: none of this plugin's skills load for {what}\n"
                  f"tags: [negative]\n{plugins_line(plugin)}max_turns: 4\nallowed_tools: [Skill, Read, Glob, Grep]\n---\n\n{prompt}\n")
            write(f"{plugin}/{name}/graders/no-plugin-skill.md",
                  f"---\ntype: tool_used\ntool: Skill\ninput_match: '{skill_re(skills)}'\nmin: 0\nmax: 0\narm: both\n---\n")
        for s, (prompt, checks) in BEHAVIOUR.get(plugin, {}).items():
            write(f"{plugin}/behaviour-{s}/prompt.md",
                  f"---\ndescription: \"applying `{s}` changes the answer — compare the with/without-plugin scores\"\n"
                  f"tags: [behaviour]\n{plugins_line(plugin)}max_turns: 12\ntimeout_seconds: 600\nallowed_tools: [Skill, Read, Glob, Grep]\n---\n\n{prompt}\n")
            for name, pattern in checks:
                quoted = pattern.replace("'", "''")
                write(f"{plugin}/behaviour-{s}/graders/{name}.md", f"---\ntype: regex\npattern: '{quoted}'\n---\n")
            write(f"{plugin}/behaviour-{s}/graders/skill-loaded.md",
                  f"---\ntype: tool_used\ntool: Skill\ninput_match: '{skill_re([s])}'\n---\n")

    def agent_case(plugin, case, fixture, prompt, description, graders):
        write(f"{plugin}/{case}/case.yaml", f'schema_version: "1.1"\nname: {case}\ncontext:\n  scaffold_script: fixture.sh\n')
        write(f"{plugin}/{case}/fixture.sh", FIXTURES[fixture], 0o755)
        write(f"{plugin}/{case}/prompt.md",
              f'---\ndescription: "{description}"\ntags: [agent]\n{plugins_line(plugin)}max_turns: 8\n'
              f"timeout_seconds: 600\nallowed_tools: [Agent, Skill, Read, Glob, Grep]\n---\n\n{prompt}\n")
        for name, body in graders.items():
            write(f"{plugin}/{case}/graders/{name}.md", body)

    for plugin, (fixture, agents) in AGENTS.items():
        for agent, prompt in agents.items():
            agent_case(plugin, f"delegate-{agent}", fixture, prompt,
                       f"the main session delegates to `{agent}` for a matching task in a {fixture} project", {
                           "agent-delegated": f"---\ntype: tool_used\ntool: Agent\ninput_match: '{agent_re([agent])}'\n---\n",
                           "agent-applies-skill": f"---\ntype: regex\ntarget: trace\npattern: '{subagent_skill_re(AGENT_SKILLS[agent])}'\n---\n",
                       })
        if plugin != "ai-toolkit-docs":
            agent_case(plugin, "no-delegate-unrelated", fixture, UNRELATED_AGENT_PROMPT,
                       "no agent of this plugin is started for an unrelated question", {
                           "no-plugin-agent": f"---\ntype: tool_used\ntool: Agent\ninput_match: '{agent_re(agents)}'\nmin: 0\nmax: 0\narm: both\n---\n",
                       })
        for case, fx, agent, prompt, why in NO_DELEGATE.get(plugin, []):
            agent_case(plugin, case, fx, prompt, why, {
                "not-delegated": f"---\ntype: tool_used\ntool: Agent\ninput_match: '{agent_re([agent])}'\nmin: 0\nmax: 0\narm: both\n---\n",
            })


def same_tree(a, b):
    cmp = filecmp.dircmp(a, b, ignore=["results"])
    if cmp.left_only or cmp.right_only or cmp.diff_files or cmp.funny_files:
        return False
    return all(same_tree(os.path.join(a, d), os.path.join(b, d)) for d in cmp.common_dirs)


def main():
    evals = os.path.join(ROOT, "evals")
    with tempfile.TemporaryDirectory() as tmp:
        generate(tmp)
        if "--check" in sys.argv:
            if not os.path.isdir(evals) or not same_tree(tmp, evals):
                print("evals/ is out of date — run: python3 tools/build-evals.py")
                sys.exit(1)
            print("Eval suites are up to date.")
            return
        for d in glob.glob(os.path.join(evals, "*")):
            if os.path.basename(d) != "results":
                shutil.rmtree(d)
        shutil.copytree(tmp, evals, dirs_exist_ok=True)
    print("Eval suites written to evals/.")


if __name__ == "__main__":
    main()

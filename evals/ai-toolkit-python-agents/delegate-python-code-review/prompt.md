---
description: "the main session delegates to `python-code-review` for a matching task in a python project"
tags: [agent]
plugins: ["../../../plugins/ai-toolkit-python-agents", "../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-python-quality", "../../../plugins/ai-toolkit-python-ops", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 8
timeout_seconds: 600
allowed_tools: [Agent, Skill, Read, Glob, Grep]
---

Use the python-code-review agent: Review my changes to src/orders/api/orders.py against our Python standards before I open the pull request. Do not change anything.

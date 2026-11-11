---
description: "no agent of this plugin is started for an unrelated question"
tags: [agent]
plugins: ["../../../plugins/ai-toolkit-python-agents", "../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-python-quality", "../../../plugins/ai-toolkit-python-ops", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 8
timeout_seconds: 600
allowed_tools: [Agent, Skill, Read, Glob, Grep]
---

In two sentences, what is the difference between a process and a thread?

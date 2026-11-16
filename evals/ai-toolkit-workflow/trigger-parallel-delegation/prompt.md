---
description: "`parallel-delegation` loads for a typical request (its description plus the plugin's routing hook)"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

I need tests added to 12 independent modules. Split the work across subagents in parallel without them stepping on each other's files.

---
description: "`code-hygiene` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Clean up my diff before review: remove comments that just restate the code, dead code, and tests that don't test anything meaningful.

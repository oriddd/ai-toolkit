---
description: "`python-security` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Protect my FastAPI order endpoints with JWT bearer tokens from our identity provider, and make sure customers can only see their own orders.

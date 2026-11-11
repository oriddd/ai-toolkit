---
description: "the main session delegates to `python-refactor` for a matching task in a python project"
tags: [agent]
plugins: ["../../../plugins/ai-toolkit-python-agents", "../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-python-quality", "../../../plugins/ai-toolkit-python-ops", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 8
timeout_seconds: 600
allowed_tools: [Agent, Skill, Read, Glob, Grep]
---

Use the python-refactor agent: src/orders/api/orders.py has business logic in the router, a module-level URL constant and bare Exceptions. Migrate it to our canonical patterns safely, step by step. The service is internal and needs no authorization; keep orders in the existing in-memory store for now.

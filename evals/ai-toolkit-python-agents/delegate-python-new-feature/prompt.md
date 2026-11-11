---
description: "the main session delegates to `python-new-feature` for a matching task in a python project"
tags: [agent]
plugins: ["../../../plugins/ai-toolkit-python-agents", "../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-python-quality", "../../../plugins/ai-toolkit-python-ops", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 8
timeout_seconds: 600
allowed_tools: [Agent, Skill, Read, Glob, Grep]
---

Use the python-new-feature agent: Implement order cancellation end to end in this FastAPI service: endpoint, persistence, a call to the payment service, validation, tests and docs. The service is internal and needs no authorization; keep orders in the existing in-memory store for now.

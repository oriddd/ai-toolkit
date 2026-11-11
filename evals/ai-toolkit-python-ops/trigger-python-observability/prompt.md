---
description: "`python-observability` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-python-ops", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-python-quality", "../../../plugins/ai-toolkit-quality", "../../../plugins/ai-toolkit-python-build"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Add structlog JSON logging with request correlation IDs and Prometheus metrics to my FastAPI app.

---
description: "`python-external-client` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

My FastAPI service needs to call the billing team's REST API to get a customer's credit limit. Add the client with proper timeouts and retries.

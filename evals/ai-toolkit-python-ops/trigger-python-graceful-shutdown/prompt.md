---
description: "`python-graceful-shutdown` loads for a typical request (its description plus the plugin's routing hook)"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-python-ops", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-python-quality", "../../../plugins/ai-toolkit-quality", "../../../plugins/ai-toolkit-python-build"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Every rolling update of our FastAPI orders service on Kubernetes gives clients 502s and connection resets, and the Kafka consumer worker sometimes reprocesses messages. Set up proper shutdown for both.

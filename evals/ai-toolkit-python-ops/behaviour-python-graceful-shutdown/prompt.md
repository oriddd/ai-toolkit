---
description: "applying `python-graceful-shutdown` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-python-ops", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-python-quality", "../../../plugins/ai-toolkit-quality", "../../../plugins/ai-toolkit-python-build"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Make my Python FastAPI service and its Kafka consumer worker shut down cleanly during Kubernetes rolling updates: show the Dockerfile CMD, the Deployment settings, the app lifespan and the worker entrypoint. Show the code in your reply. Do not create files.

---
description: "`python-cd` loads for a typical request (its description plus the plugin's routing hook)"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-python-ops", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-python-quality", "../../../plugins/ai-toolkit-quality", "../../../plugins/ai-toolkit-python-build"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

We need to deploy our FastAPI orders service and its Kafka consumer worker to Kubernetes. Write the Helm chart, including how the Alembic migrations run on each release.

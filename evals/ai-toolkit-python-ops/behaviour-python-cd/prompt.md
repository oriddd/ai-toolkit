---
description: "applying `python-cd` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-python-ops", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-python-quality", "../../../plugins/ai-toolkit-quality", "../../../plugins/ai-toolkit-python-build"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Write the Helm chart (values.yaml and templates) to deploy my Python FastAPI service, its Kafka worker process and its Alembic migrations to Kubernetes. Show the code in your reply. Do not create files.

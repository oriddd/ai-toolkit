---
description: "applying `python-integration-tests` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-python-quality", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Integration-test my Python SqlOrderRepository (SQLAlchemy async) against a real PostgreSQL. Show the code in your reply. Do not create files.

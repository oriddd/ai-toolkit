---
description: "applying `python-persistence` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Add an orders table to my Python FastAPI service with SQLAlchemy 2.0 async, a repository and an Alembic migration; concurrent updates must not overwrite each other. Show the code in your reply. Do not create files.

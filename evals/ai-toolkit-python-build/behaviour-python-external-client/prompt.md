---
description: "applying `python-external-client` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

My Python FastAPI service must call the Inventory API: GET /items/{item_id}; a 404 means the item does not exist. Show the code in your reply. Do not create files.

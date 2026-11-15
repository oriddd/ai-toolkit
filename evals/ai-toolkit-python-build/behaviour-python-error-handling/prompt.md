---
description: "applying `python-error-handling` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

In my Python FastAPI service OrderService.get(order_id) must fail when the order does not exist, and the API must answer 404. Show the code in your reply. Do not create files.

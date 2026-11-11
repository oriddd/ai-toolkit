---
description: "applying `python-input-validation` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Validate a Python FastAPI booking request: a valid email, guests between 1 and 10, and check_out must be after check_in. Show the code in your reply. Do not create files.

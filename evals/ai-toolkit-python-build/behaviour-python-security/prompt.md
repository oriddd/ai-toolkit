---
description: "applying `python-security` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Protect POST /v1/orders in my Python FastAPI service with JWT bearer tokens from our Keycloak; only callers with scope orders:write may create, and customers may read only their own orders. Show the code in your reply. Do not create files.

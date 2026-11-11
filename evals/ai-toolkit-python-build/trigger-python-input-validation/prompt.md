---
description: "`python-input-validation` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Validate my FastAPI sign-up request with pydantic: the password needs at least 12 characters and confirm_password must match password.

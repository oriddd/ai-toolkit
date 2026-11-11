---
description: "`python-error-handling` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

In my FastAPI app, when a user is not found I raise a bare Exception and the client gets a 500. Set up proper error handling with typed exceptions.

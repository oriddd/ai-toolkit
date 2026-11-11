---
description: "`exception-handling` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-build", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

In my Spring Boot service, when an order is not found the controller returns a 500 with a stack trace. Set up proper error handling so it returns a 404 with a clean error body.

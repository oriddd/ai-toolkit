---
description: "`request-metrics` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

I need a Micrometer timer for the POST /orders endpoint of our Spring Boot app, tagged by client id and response status.

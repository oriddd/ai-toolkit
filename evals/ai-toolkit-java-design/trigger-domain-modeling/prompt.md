---
description: "`domain-modeling` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Model the Order aggregate for our Spring Boot service: order lines, a Money value object, and an OrderPlaced domain event.

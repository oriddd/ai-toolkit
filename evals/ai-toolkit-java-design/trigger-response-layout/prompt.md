---
description: "`response-layout` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Clients want GET /products/{id}?layout=summary to return only id and name, and ?layout=full to return every field. Implement this in our Spring Boot API.

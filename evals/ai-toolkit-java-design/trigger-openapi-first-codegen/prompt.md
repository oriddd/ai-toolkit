---
description: "`openapi-first-codegen` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

We keep our OpenAPI spec in api.yaml. Set up the Spring Boot Maven build to generate the controllers and DTOs from it.

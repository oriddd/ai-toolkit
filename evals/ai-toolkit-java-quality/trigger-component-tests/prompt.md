---
description: "`component-tests` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Write tests that boot my whole Spring Boot application and call the /orders REST API end to end, with the downstream HTTP clients replaced by fakes.

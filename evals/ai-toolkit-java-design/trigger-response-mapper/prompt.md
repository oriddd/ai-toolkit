---
description: "`response-mapper` loads for a typical request (its description plus the plugin's routing hook)"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

We need to serve v1 and v2 of the Customer response from the same Spring Boot endpoint, with the version chosen by the Accept header.

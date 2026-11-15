---
description: "`async-api-patterns` loads for a typical request (its description plus the plugin's routing hook)"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Our Spring Boot report-generation endpoint takes up to three minutes and clients time out. How should the API handle this long-running operation?

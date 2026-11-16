---
description: "`validation-pattern` loads for a typical request (its description plus the plugin's routing hook)"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-build", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Explain why our Spring Boot standard puts validation rules in custom annotations, validators and rule beans instead of if/throw checks in services, and how those validators should be tested.

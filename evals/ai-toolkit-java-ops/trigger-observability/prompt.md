---
description: "`observability` loads for a typical request (its description plus the plugin's routing hook)"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Add JSON structured logging with correlation IDs and OpenTelemetry tracing to our Spring Boot service.

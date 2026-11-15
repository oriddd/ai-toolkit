---
description: "`spring-boot-conventions` loads for a typical request (its description plus the plugin's routing hook)"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

My Spring Boot service reads a dozen payment.* settings with @Value annotations scattered across classes. What's the right way to bind this configuration?

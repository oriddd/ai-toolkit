---
description: "`feature-flags` loads for a typical request (its description plus the plugin's routing hook)"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

I want to ship the new recommendation engine in our Spring Boot app switched off, and later enable it for 10% of users without redeploying.

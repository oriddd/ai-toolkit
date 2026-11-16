---
description: "`permissions` loads for a typical request (its description plus the plugin's routing hook)"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-build", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

In our Spring Boot API, only the owner of a document or an admin service account may delete it. Implement that authorization check.

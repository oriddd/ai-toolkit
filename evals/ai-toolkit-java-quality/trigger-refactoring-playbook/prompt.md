---
description: "`refactoring-playbook` loads for a typical request (its description plus the plugin's routing hook)"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Migrate our legacy Spring Boot code from RestTemplate to RestClient step by step, without breaking anything along the way.

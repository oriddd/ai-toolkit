---
description: "`testable-code-principles` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

This Spring Boot service class uses static helper methods and a global singleton, and it's impossible to unit test. Which design principles should I follow to make it testable?

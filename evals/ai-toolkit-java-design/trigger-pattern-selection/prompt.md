---
description: "`pattern-selection` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Before I write it: for our two Spring Boot notification channels (email and SMS), should I introduce an abstraction layer with a registry, or is that over-engineering at this scale?

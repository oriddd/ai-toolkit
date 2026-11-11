---
description: "`adapter-contract-tests` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Our Spring Boot app has a CachePort with a Redis adapter and a new Caffeine adapter. How do I prove both adapters behave identically with one shared test suite?

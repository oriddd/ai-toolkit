---
description: "`pluggable-architecture` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Our Spring Boot services call Redis directly for caching. We want to swap Redis for Infinispan, or run both, purely by configuration. How should I restructure it?

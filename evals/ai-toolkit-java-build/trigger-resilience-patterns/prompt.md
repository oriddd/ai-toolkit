---
description: "`resilience-patterns` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-build", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Our Spring Boot service hangs whenever the downstream pricing service is slow. Add timeouts, a circuit breaker and a fallback around that call.

---
description: "`graceful-shutdown` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

During Kubernetes rolling updates our Spring Boot pods drop in-flight requests and clients see 502s. Fix the shutdown behaviour.

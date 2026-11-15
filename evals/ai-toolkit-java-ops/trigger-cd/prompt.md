---
description: "`cd` loads for a typical request (its description plus the plugin's routing hook)"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Write a Helm chart to deploy our Spring Boot service to Kubernetes, with readiness and liveness probes and autoscaling.

---
description: "applying `graceful-shutdown` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
allowed_tools: [Skill, Read, Glob, Grep]
---

During Kubernetes rolling updates our Spring Boot 3 pods drop in-flight requests and @Async tasks. Show the application and Kubernetes configuration that fixes it.

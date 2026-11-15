---
description: "applying `graceful-shutdown` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

During Kubernetes rolling updates our Spring Boot 3.5 pods drop in-flight HTTP requests and @Async tasks, and the Kafka listener in the same service sometimes stops mid-batch. The pod spec has terminationGracePeriodSeconds: 30. Show the application and Kubernetes configuration that fixes it.

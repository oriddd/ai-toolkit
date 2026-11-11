---
description: "applying `external-client` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-java-build", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

My Spring Boot 3 service must call the Inventory REST API: GET /items/{id} returns an item, and a 404 means the item does not exist. Show me, in your reply, the Java package and classes you would write for this integration (class names and their code). Do not create files.

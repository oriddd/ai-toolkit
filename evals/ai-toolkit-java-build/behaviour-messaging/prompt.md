---
description: "applying `messaging` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-java-build", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

When an order is created in my Spring Boot 3 order service, publish an OrderPlaced event to Kafka; the shipping service consumes it. Make sure no event is lost if the database commit succeeds, and that redelivered events are not processed twice. Show the code in your reply. Do not create files.

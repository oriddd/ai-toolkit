---
description: "applying `exception-handling` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-java-build", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
allowed_tools: [Skill, Read, Glob, Grep]
---

In my Spring Boot 3 service, OrderService.getOrder(id) should fail when the order does not exist, and the API must answer 404. Show me, in your reply, the Java code for the exception and how it becomes the HTTP response. Do not create files.

---
description: "applying `spring-boot-conventions` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

My Spring Boot 3 service reads payment.base-url, payment.timeout and payment.retries with @Value in three different classes. Show me, in your reply, the Java code you would replace that with. Do not create files.

---
description: "applying `request-metrics` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Add a Micrometer timer for POST /orders in my Spring Boot 3 service, tagged with the client id and the response status; more endpoints will get their own timers later. Show the code in your reply. Do not create files.

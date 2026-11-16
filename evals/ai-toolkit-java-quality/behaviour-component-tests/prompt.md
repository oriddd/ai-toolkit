---
description: "applying `component-tests` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Write a component test for my Spring Boot 3 service: boot the whole application, call POST /orders over HTTP, and replace the downstream InventoryClient with a deterministic fake. The service stores orders through a Spring Data JPA OrderRepository on PostgreSQL, and the test must run without a database: show the test profile yaml as well. Show the code in your reply. Do not create files.

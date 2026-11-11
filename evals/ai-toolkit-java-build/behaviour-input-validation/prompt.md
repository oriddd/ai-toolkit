---
description: "applying `input-validation` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-java-build", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
allowed_tools: [Skill, Read, Glob, Grep]
---

In my Spring Boot 3 API, CreateOrderRequest has orderDate, deliveryDate and sku. deliveryDate must be after orderDate, and sku must be a code the injected SkuCatalogue bean recognises. Add these validation rules. Show the code in your reply. Do not create files.

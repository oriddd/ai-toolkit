---
description: "applying `persistence` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-java-build", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
allowed_tools: [Skill, Read, Glob, Grep]
---

Add persistence for an Invoice (number, customerId, amount, status) to my Spring Boot 3 service: the JPA entity, the Spring Data repository with a query listing a customer's invoices, and the database migration. Show the code in your reply. Do not create files.

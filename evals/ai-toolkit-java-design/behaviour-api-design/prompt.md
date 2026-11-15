---
description: "applying `api-design` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Design the REST API for invoices in our Spring Boot service: list a customer's invoices, get one invoice, and export an invoice as PDF. Give the endpoints with methods, status codes and an example error body.

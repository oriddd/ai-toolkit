---
description: "the main session delegates to `new-feature` for a matching task in a java project"
tags: [agent]
plugins: ["../../../plugins/ai-toolkit-java-agents", "../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-build", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-scaffold", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 8
timeout_seconds: 600
allowed_tools: [Agent, Skill, Read, Glob, Grep]
---

Use the new-feature agent: Implement order cancellation end to end in this service: a new endpoint, persisting the cancellation, notifying the payment service over HTTP, validation, tests and docs. Orders are stored through OrderRepository (Spring Data JPA, PostgreSQL); the API is internal and needs no authorization.

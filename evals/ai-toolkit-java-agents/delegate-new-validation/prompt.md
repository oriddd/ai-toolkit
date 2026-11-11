---
description: "the main session delegates to `new-validation` for a matching task in a java project"
tags: [agent]
plugins: ["../../../plugins/ai-toolkit-java-agents", "../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-build", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-scaffold", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 8
timeout_seconds: 600
allowed_tools: [Agent, Skill, Read, Glob, Grep]
---

Use the new-validation agent: Add a validation rule to this service: an order's quantity must be between 1 and 100, and its sku must match the format ABC-12345 (three capital letters, a dash, five digits). Orders are stored through OrderRepository (Spring Data JPA, PostgreSQL); the API is internal and needs no authorization.

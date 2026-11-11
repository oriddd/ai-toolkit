---
description: "the main session delegates to `new-microservice-client` for a matching task in a java project"
tags: [agent]
plugins: ["../../../plugins/ai-toolkit-java-agents", "../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-build", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-scaffold", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 8
timeout_seconds: 600
allowed_tools: [Agent, Skill, Read, Glob, Grep]
---

Use the new-microservice-client agent: Integrate the Inventory service's REST API (GET /items/{id}) into this service as a new downstream client. Orders are stored through OrderRepository (Spring Data JPA, PostgreSQL); the API is internal and needs no authorization.

---
description: "the main session picks `test-writer` for a matching task without being told its name"
tags: [agent]
plugins: ["../../../plugins/ai-toolkit-java-agents", "../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-build", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-scaffold", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 30
timeout_seconds: 1200
allowed_tools: [Agent, Skill, Read, Glob, Grep, Write, Edit]
---

The production code is done. Write JUnit tests for OrderService and for OrderController — they are independent, so do them in parallel. OrderService also POSTs to the payment service through a RestTemplate it creates itself; do not change production code — write characterisation tests through the HTTP API with the payment service stubbed. The API is internal and needs no authorization.

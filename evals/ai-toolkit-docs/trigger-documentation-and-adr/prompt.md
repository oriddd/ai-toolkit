---
description: "`documentation-and-adr` loads for a typical request (its description plus the plugin's routing hook)"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

We decided to move our order events from RabbitMQ to Kafka. Record that decision for the repository as an Architecture Decision Record.

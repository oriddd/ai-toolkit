---
description: "applying `documentation-and-adr` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Our repository already has ADRs 0001 to 0004; ADR 0003 chose RabbitMQ for order events. We have now decided to move order events to Kafka. Write the Architecture Decision Record, say where the file goes, and say what changes in the existing ADRs. Show it in your reply; do not create files.

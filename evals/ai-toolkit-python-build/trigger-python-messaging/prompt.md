---
description: "`python-messaging` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

When an order is placed in my FastAPI + SQLAlchemy service, publish an OrderPlaced event to Kafka reliably, and make sure the billing service never processes it twice.

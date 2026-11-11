---
description: "applying `python-messaging` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-python-build", "../../../plugins/ai-toolkit-python-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
allowed_tools: [Skill, Read, Glob, Grep]
---

Publish an OrderPlaced event to Kafka when an order is created in my Python FastAPI/SQLAlchemy service, and consume it in the billing service. Show the code in your reply. Do not create files.

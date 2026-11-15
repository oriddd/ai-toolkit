---
description: "applying `uml-diagram` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Draw the system context of our order service (customers, API gateway, order service, PostgreSQL, Kafka, payment provider) and the checkout sequence for the repository docs. Our repository keeps AI context docs under context/. Show the diagrams and where each file goes; do not create files.

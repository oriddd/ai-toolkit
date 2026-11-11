---
description: "applying `domain-modeling` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Model the Order aggregate for our Spring Boot service: order lines, a total in Money, an OrderPlaced domain event when the order is placed, and a rule that a placed order cannot get new lines. Show the code in your reply. Do not create files.

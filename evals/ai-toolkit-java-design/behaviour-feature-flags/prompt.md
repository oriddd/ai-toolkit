---
description: "applying `feature-flags` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
allowed_tools: [Skill, Read, Glob, Grep]
---

We want to ship a new invoice-pricing algorithm in our Spring Boot service switched off, then enable it for some tenants without redeploying, and remove the old algorithm later. Show the code in your reply. Do not create files.

---
description: "applying `sonar-quality-gate` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

SonarQube's quality gate fails on pull request #482 of my Spring Boot Maven service (Sonar project key shop-orders, base branch main): new-code coverage is 72% against a gate of 80%. Show me the exact commands you would use to read the gate result and the open new-code issues, and to re-run the analysis from my machine if that is needed. Do not run anything and do not create files.

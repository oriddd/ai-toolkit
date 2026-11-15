---
description: "applying `sonar-quality-gate` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

SonarQube's quality gate fails on my Spring Boot pull request: new-code coverage is 72% against a gate of 80%, and there are 3 cognitive-complexity code smells in PricingService. Get the gate green. Show the code in your reply. Do not create files.

---
description: "applying `release-versioning` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Set up automated releases for our Spring Boot service's GitHub repository: semantic versions derived from the commits, a generated CHANGELOG, and the image tag equal to the version. Show the code in your reply. Do not create files.

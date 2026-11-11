---
description: "applying `permissions` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-java-build", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
allowed_tools: [Skill, Read, Glob, Grep]
---

In my Spring Boot 3 API, a document may be deleted only by its owner (an end user) or by an admin service account; any other caller gets 403. Implement this authorization. Show the code in your reply. Do not create files.

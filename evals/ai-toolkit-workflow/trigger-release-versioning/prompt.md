---
description: "`release-versioning` loads for a typical request (its description plus the plugin's routing hook)"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Set up automated releases for our repository with semantic versioning and a generated CHANGELOG.

---
description: "`github-actions-ci` loads for a typical request (its description plus the plugin's routing hook)"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

Our Spring Boot service lives on GitHub. Create GitHub Actions workflows to build, test and publish its Docker image.

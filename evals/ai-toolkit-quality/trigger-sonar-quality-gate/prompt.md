---
description: "`sonar-quality-gate` loads for a typical request (its description plus the plugin's routing hook)"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

SonarQube says the quality gate failed on my branch because of new code smells and low coverage on new code. Get it back to green.

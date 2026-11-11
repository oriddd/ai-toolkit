---
description: "the main session delegates to `code-review` for a matching task in a java project"
tags: [agent]
plugins: ["../../../plugins/ai-toolkit-java-agents", "../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-java-build", "../../../plugins/ai-toolkit-java-quality", "../../../plugins/ai-toolkit-java-ops", "../../../plugins/ai-toolkit-java-scaffold", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 8
timeout_seconds: 600
allowed_tools: [Agent, Skill, Read, Glob, Grep]
---

Use the code-review agent: Review my changes to OrderController.java and OrderService.java against our Java standards before I open the pull request. Do not change anything.

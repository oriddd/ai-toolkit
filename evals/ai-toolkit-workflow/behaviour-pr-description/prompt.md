---
description: "applying `pr-description` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Write the pull request description for my branch. It adds retry with exponential backoff to PaymentClient (max 3 attempts), makes the backoff configurable in application.yaml, and adds PaymentClientRetryTest. Show it in your reply; do not call any git host.

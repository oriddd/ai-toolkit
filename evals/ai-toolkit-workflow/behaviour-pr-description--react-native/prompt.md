---
description: "applying `pr-description` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Write the pull request description for my branch. It adds an optimistic update to the add-to-cart button on CartScreen through a new useAddToCart mutation hook, makes the retry count configurable in app.config.ts, and adds useAddToCart.test.tsx. Show it in your reply; do not call any git host.

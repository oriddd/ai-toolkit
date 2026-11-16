---
description: "applying `git-commit-conventions` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

Write the git commit message for this change and show it in your reply (do not run git): in our published React Native utilities package I renamed the public function formatPrice to formatCurrency, since it now takes a locale, and updated the three call sites inside the package.

---
description: "applying `parallel-delegation` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

I need three independent additions to my Expo React Native app: a new analytics tracker hook for the export screen, a new zod schema for SKU format, and unit tests for the existing InvoiceList component. Plan how you would split this across subagents and write the brief you would send to each. Do not create files.

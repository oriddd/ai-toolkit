---
description: "applying `parallel-delegation` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

I need three independent additions to my FastAPI service: a new Prometheus metrics recorder for the export endpoint, a new Pydantic validator for SKU format, and unit tests for the existing InvoiceService. Plan how you would split this across subagents and write the brief you would send to each. Do not create files.

---
description: "the main session delegates to `update-context` for a matching task in a java project"
tags: [agent]
plugins: ["../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 8
timeout_seconds: 600
allowed_tools: [Agent, Skill, Read, Glob, Grep]
---

Use the update-context agent: I just added order creation to this service — POST /api/v1/orders in OrderController, OrderService saves through OrderRepository and notifies the payment service, and migration V001__init.sql creates the orders table. Bring the project's context docs, progress tracker and CHANGELOG in line with that change; create them if they do not exist yet.

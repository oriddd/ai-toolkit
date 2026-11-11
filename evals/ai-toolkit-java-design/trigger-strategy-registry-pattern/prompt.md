---
description: "`strategy-registry-pattern` loads for a typical request, routed by its description alone"
tags: [trigger]
plugins: ["../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 4
allowed_tools: [Skill, Read, Glob, Grep]
---

My Spring Boot code has a growing if/else on paymentType (CARD, PAYPAL, BANK_TRANSFER) and we add a new type every quarter. Restructure it so a new type never touches the dispatching code.

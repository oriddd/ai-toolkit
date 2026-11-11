---
description: "applying `strategy-registry-pattern` changes the answer — compare the with/without-plugin scores"
tags: [behaviour]
plugins: ["../../../plugins/ai-toolkit-java-design", "../../../plugins/ai-toolkit-quality"]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
---

My Spring Boot 3 PaymentService has a growing if/else on paymentType (CARD, PAYPAL, BANK_TRANSFER) and a new type arrives every quarter. Restructure it so adding a type never touches the dispatching code. Show the code in your reply. Do not create files.

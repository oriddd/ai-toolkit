---
description: "the main session delegates to `react-native-new-feature` for a matching task in a react-native project"
tags: [agent]
plugins: ["../../../plugins/ai-toolkit-react-native-agents", "../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-react-native-design", "../../../plugins/ai-toolkit-react-native-build", "../../../plugins/ai-toolkit-react-native-quality", "../../../plugins/ai-toolkit-react-native-ops", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 8
timeout_seconds: 600
allowed_tools: [Agent, Skill, Read, Glob, Grep]
---

Use the react-native-new-feature agent: Implement a wishlist feature end to end in this React Native app: a Wishlist screen in the root stack, the data layer on the existing api client (src/api/client.ts) — GET /wishlist returns { items: { productId: string, name: string }[] }, POST /wishlist { productId } adds, DELETE /wishlist/{productId} removes — with optimistic add/remove, validation, error handling and tests. No authentication changes are needed.

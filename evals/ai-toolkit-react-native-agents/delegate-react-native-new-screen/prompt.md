---
description: "the main session delegates to `react-native-new-screen` for a matching task in a react-native project"
tags: [agent]
plugins: ["../../../plugins/ai-toolkit-react-native-agents", "../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-react-native-design", "../../../plugins/ai-toolkit-react-native-build", "../../../plugins/ai-toolkit-react-native-quality", "../../../plugins/ai-toolkit-react-native-ops", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 8
timeout_seconds: 600
allowed_tools: [Agent, Skill, Read, Glob, Grep]
---

Use the react-native-new-screen agent: Add an OrderDetails screen to this React Native app, added to the root stack in src/navigation/RootNavigator.tsx with an orderId param and opened from OrdersScreen. It shows one order from GET /orders/{id} on the existing api client (src/api/client.ts), which returns { id: string, status: 'PENDING' | 'SHIPPED', total: number }. No authentication changes are needed.

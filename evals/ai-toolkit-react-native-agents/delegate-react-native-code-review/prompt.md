---
description: "the main session delegates to `react-native-code-review` for a matching task in a react-native project"
tags: [agent]
plugins: ["../../../plugins/ai-toolkit-react-native-agents", "../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-react-native-design", "../../../plugins/ai-toolkit-react-native-build", "../../../plugins/ai-toolkit-react-native-quality", "../../../plugins/ai-toolkit-react-native-ops", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 8
timeout_seconds: 600
allowed_tools: [Agent, Skill, Read, Glob, Grep]
---

Use the react-native-code-review agent: Review my changes to src/screens/LoginScreen.tsx against our React Native standards before I open the pull request. Do not change anything.

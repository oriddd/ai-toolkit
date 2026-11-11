---
description: "the main session delegates to `react-native-test-writer` for a matching task in a react-native project"
tags: [agent]
plugins: ["../../../plugins/ai-toolkit-react-native-agents", "../../../plugins/ai-toolkit-docs", "../../../plugins/ai-toolkit-react-native-design", "../../../plugins/ai-toolkit-react-native-build", "../../../plugins/ai-toolkit-react-native-quality", "../../../plugins/ai-toolkit-react-native-ops", "../../../plugins/ai-toolkit-workflow", "../../../plugins/ai-toolkit-quality"]
max_turns: 8
timeout_seconds: 600
allowed_tools: [Agent, Skill, Read, Glob, Grep]
---

Use the react-native-test-writer agent: The production code is done. Write the Jest and React Native Testing Library tests for the existing LoginScreen component. The backend API already exists at https://api.example.com; no authentication changes are needed.

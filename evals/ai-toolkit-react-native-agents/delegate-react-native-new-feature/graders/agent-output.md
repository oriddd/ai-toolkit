---
type: regex
target: trace
pattern: '"parent_tool_use_id":"[^"]+"[^\n]*(?:File created successfully at: [^\x22]*src/\S+\.tsx?|The file [^\x22]*src/\S+\.tsx? has been updated)|(?:File created successfully at: [^\x22]*src/\S+\.tsx?|The file [^\x22]*src/\S+\.tsx? has been updated)[^\n]*"parent_tool_use_id":"[^"]+"'
---

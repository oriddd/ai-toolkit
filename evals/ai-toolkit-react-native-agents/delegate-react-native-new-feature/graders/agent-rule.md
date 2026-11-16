---
type: regex
target: trace
pattern: '"parent_tool_use_id":"[^"]+"[^\n]*"name":"(?:Write|Edit)","input":\{"file_path":"[^"]*src/\S+\.tsx?[^"]*",[^\n]{0,80}?"(?:content|new_string)":"(?:[^"\\]|\\.)*accessibilityRole|"name":"(?:Write|Edit)","input":\{"file_path":"[^"]*src/\S+\.tsx?[^"]*",[^\n]{0,80}?"(?:content|new_string)":"(?:[^"\\]|\\.)*accessibilityRole[^\n]*"parent_tool_use_id":"[^"]+"'
---

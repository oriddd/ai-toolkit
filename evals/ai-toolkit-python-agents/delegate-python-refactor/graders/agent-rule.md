---
type: regex
target: trace
pattern: '"parent_tool_use_id":"[^"]+"[^\n]*"name":"(?:Write|Edit)","input":\{"file_path":"[^"]*src/orders/\S+\.py[^"]*",[^\n]{0,80}?"(?:content|new_string)":"(?:[^"\\]|\\.)*BaseSettings|"name":"(?:Write|Edit)","input":\{"file_path":"[^"]*src/orders/\S+\.py[^"]*",[^\n]{0,80}?"(?:content|new_string)":"(?:[^"\\]|\\.)*BaseSettings[^\n]*"parent_tool_use_id":"[^"]+"'
---

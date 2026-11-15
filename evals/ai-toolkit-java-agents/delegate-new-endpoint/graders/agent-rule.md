---
type: regex
target: trace
pattern: '"parent_tool_use_id":"[^"]+"[^\n]*"name":"(?:Write|Edit)","input":\{"file_path":"[^"]*src/test/java/\S+Test\.java[^"]*",[^\n]{0,80}?"(?:content|new_string)":"(?:[^"\\]|\\.)*void [a-z]\w*_\w+_\w+\(|"name":"(?:Write|Edit)","input":\{"file_path":"[^"]*src/test/java/\S+Test\.java[^"]*",[^\n]{0,80}?"(?:content|new_string)":"(?:[^"\\]|\\.)*void [a-z]\w*_\w+_\w+\([^\n]*"parent_tool_use_id":"[^"]+"'
---

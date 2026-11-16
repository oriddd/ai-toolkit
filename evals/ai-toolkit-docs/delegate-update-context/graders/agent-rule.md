---
type: regex
target: trace
pattern: '"parent_tool_use_id":"[^"]+"[^\n]*"name":"(?:Write|Edit)","input":\{"file_path":"[^"]*(?:context/\S+\.md|CHANGELOG\.md)[^"]*",[^\n]{0,80}?"(?:content|new_string)":"(?:[^"\\]|\\.)*## \d\. [^\\\x22]{3,60}\(REQUIRED|"name":"(?:Write|Edit)","input":\{"file_path":"[^"]*(?:context/\S+\.md|CHANGELOG\.md)[^"]*",[^\n]{0,80}?"(?:content|new_string)":"(?:[^"\\]|\\.)*## \d\. [^\\\x22]{3,60}\(REQUIRED[^\n]*"parent_tool_use_id":"[^"]+"'
---

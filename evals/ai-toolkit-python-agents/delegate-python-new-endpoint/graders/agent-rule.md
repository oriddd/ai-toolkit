---
type: regex
target: trace
pattern: '"parent_tool_use_id":"[^"]+"[^\n]*"name":"(?:Write|Edit)","input":\{"file_path":"[^"]*tests/\S+\.py[^"]*",[^\n]{0,80}?"(?:content|new_string)":"(?:[^"\\]|\\.)*def test_[a-z]\w*_[a-z]+[A-Z]\w*|"name":"(?:Write|Edit)","input":\{"file_path":"[^"]*tests/\S+\.py[^"]*",[^\n]{0,80}?"(?:content|new_string)":"(?:[^"\\]|\\.)*def test_[a-z]\w*_[a-z]+[A-Z]\w*[^\n]*"parent_tool_use_id":"[^"]+"'
---

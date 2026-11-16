---
type: regex
pattern: '(?:^|\n)\W*(?:GET|POST)\s+\S*/invoices/\{\w+\}/(?:export|pdf)\b(?!s)'
match: not_contains
---

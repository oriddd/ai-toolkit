---
type: regex
pattern: '(?:^|\n)[ \t]*(?:/\*\*|\*)[ \t]*(?:Service for order totals|The tax rate\.?|Constructor\.?|Gets the tax rate)|(?:^|\n)[ \t]*(?:/?\*+)?[ \t]*@author|(?:^|\n)[ \t]*//[ \t]*public BigDecimal oldTotal|(?:^|\n)[ \t]*//[ \t]*calculate total|return net\.add\([^\n]*;[ \t]*//'
match: not_contains
---

# The grammar of the language

Principles:

- The grammar should be minimalistic.
- There should be no keywords.
- The grammar should support incremental parsing.
- For readability, inline statements must fit completely on one line.
- It shouldn't be necessary to place backslash on each line of a multiline statement.

The grammar is mostly space-insensitive. Nested backslashes are rejected. They are considered confusing.

TODO: I think the current grammar doesn't work since regular_statements can't end?
TODO: look at ./simplified_grammar.md for a solution and update the grammar.

```text
input := { regular_statement } <end of input> ;

regular_statement :=
  | '\n'
  | '#' ' ' comment_line
  | regular_statement_part regular_statement
;

regular_statement_part :=
  | '\\' multiline_statement_part
  | statement_part(substatement)
;

multiline_statement_part :=
  | ';'
  | '\n' [ '#' ' ' comment_line ] multiline_statement_part
  | statement_part(substatement) multiline_statement_part
;

substatement :=
  | '\n' { regular_statement } ')'
  | inline_statement
;

inline_statement :=
  | ')'
  | statement_part(inline_statement)
;

statement_part(inner_statement) := [ '$' ] ( '(' inner_statement | string )

comment_line := { ! '\n' } '\n'

string := '\'' quoted_string | bare_string ;

quoted_string :=
  | '\'' [ '\\' quoted_string ]
  | <any character> quoted_string
;

bare_string := { ! ( '\n' | ')' ) } non_consuming(')' | <whitespace>)
```

# Example scripts

```
let make-adder (
  let amount $1
  let count 0
  => (
    set count $(add $count $amount)
    => $count
  )
)

let my-list $(list 1 2 3 4 5)
let sum $(
  let index 0
  let sum 0
  while (!= $index $(my-list len)) (
    set sum $(add $sum $(my-list at $index))
  )
  => $sum
)

let long-commented-list $(
  list \
    # A.
    a
    # B.
    b
    # C.
    c
    # D.
    d
    # E.
    e
  ;
)
```

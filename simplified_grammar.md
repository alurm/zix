```text
block :=
  | ')'
  | statement block
;

statement :=
  | '\n'
  | expression statement
;

expression :=
  | [ '$' ] '(' '\n' block
  | string
;
```

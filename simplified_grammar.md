```text
block :=
  | ')'
  | statement block
;

statement :=
  | '\n'
  | expression statement
;

expression := [ '$' ] (
  | '(' block
  | string
) ;
```

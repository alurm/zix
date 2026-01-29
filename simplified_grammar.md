TODO: maybe should support ; for separating statements probably. Might be useful for fake shebangs.

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

# Musings

## Error/variant handling.

What should the value of $() be? Failure?

## Stack unwinding mechanism

throw value

let result $(catch (add 1 2))

## Tagged data

## Modules

let module $(eval (
  let foo 3
  let bar 4
))

let m $(module)
module let 

## Values in the syntax tree

## Testing

if (eq 1 2) throw
if (eq 1 2) halt

## Should blocks which do not return fail?

let counterer (
  let count 0
  return (
    set count $(add $count 1)
    return $count
  )
)

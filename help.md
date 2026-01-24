# Statements

Statements look like this:

    <command expression> <argument expressions>.

Argument expressions are separated from each other with a space character.

Example:

    # This is a comment (not a statement).
    # Comments are ignored by the interpreter.
    # Comments start with `#` and span until the end of the line.
    # The value of this statement is the string `Hello, world!`.
    <= 'Hello, world!'

# Expressions

There are multiple types of expressions: strings literals, blocks and closures.

## String literals

String literals are strings present in code literally. There are two types of string literals: bare strings and quoted strings.

The value of a string literal is the string it represents.

### Bare strings

Bare strings are called bare because they have no special characters in them and therefore can be typed as-is, without quoting.

Examples:

    Hello

### Quoted strings

Quoted strings start and end with a single quote.
All repeated single quotes are interpreted as a single quote.
All other characters in the quoted string are interpreted as-is.

Example:

    'John''s pizza'

## Variables

Variables look like strings preceded by `$`.

Example:

    # This statement creates a variable named `x` and sets its value to the string `3`.
    let x 3
    # We can refer to this variable now by typing `$x`.
    <= $x

(Under the hood, syntax `$x` gets transformed into `$(get x)`. Therefore, by redefining `get` a custom variable resolver can be installed.)

## Blocks and closures

Blocks and closures are containers of statements.

### Blocks

Blocks execute immediately when seen.
The value of a block is the value of the last statement in the block.

Example:

    # $(+ 2 3) is a block. It's value is the string 5.
    + 1 $(+ 2 3)

### Closures

Closures are similar to blocks, but they do not execute immediately.

Example:

    let counter $(
        # This variable is owned by the current block.
        let count 0
        # The value of the block is this closure.
        <= (
            # Increment the count.
            set count $(+ $count 1)
            # Return the updated count.
            <= $count
        )
    )
    # Will return the string 1.
    counter
    # Will return the string 2.
    counter

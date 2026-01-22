// TODO: fix error reporting.

const Parser = @import("parser.zig");

const Self = @This();
const std = @import("std");

words: std.StringHashMapUnmanaged(Value) = .empty,

const Value = union(enum) {
    string: []const u8,
    builtin: []const u8,
    // Have this for now.
    nothing: void,
};

pub fn evaluate_expression(self: *Self, expression: Parser.Expression) !Value {
    _ = self;

    return switch (expression) {
        .string => |string| .{ .string = string },
        else => error.ExpressionTypeNotImplemented,
    };
}

pub fn default(allocator: std.mem.Allocator) !@This() {
    var words: std.StringHashMapUnmanaged(Value) = .empty;

    // FIXME: this is annoying how this must be in sync.
    for ([_][]const u8{ "get", "let", "set", "help", "=>" }) |builtin|
        try words.put(allocator, builtin, .{ .builtin = builtin });
    return .{
        .words = words,
    };
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn evaluate_statement(
    self: *Self,
    allocator: std.mem.Allocator,
    statement: Parser.Statement,
) !Value {
    const command = blk: {
        const value = try self.evaluate_expression(statement.command);
        break :blk switch (value) {
            .string => |string| if (self.words.get(string)) |val| val else return error.CommandNotFound,
            else => value,
        };
    };

    const arguments = try allocator.alloc(Value, statement.arguments.len);
    defer allocator.free(arguments);

    for (statement.arguments, 0..) |argument, i|
        arguments[i] = try self.evaluate_expression(argument);

    switch (command) {
        .string => return error.ValueOfCommandIsString,
        .builtin => |builtin| return if (std.mem.eql(u8, builtin, "get")) {
            if (self.words.get(arguments[0].string)) |value| return value;
            return error.WordNotDefined;
        } else if (eq(builtin, "let")) {
            // FIXME: use stack.
            // This is broken btw. Implement a GC.
            const name = try allocator.dupe(u8, arguments[0].string);
            const value = arguments[1];
            try self.words.put(allocator, name, value);
            return .nothing;
        } else if (eq(builtin, "=>")) {
            // FIXME: rename this?
            // FIXME: this is broken.
            return arguments[0];
        } else if (eq(builtin, "set")) {
            // FIXME: use stack.
            // This is broken btw. Implement a GC.
            const name = try allocator.dupe(u8, arguments[0].string);
            const value = arguments[1];
            try self.words.put(allocator, name, value);
            return .nothing;
        } else if (eq(builtin, "help")) {
            // FIXME: consider not using debug.print.

            if (arguments.len == 0) {
                std.debug.print(
                    \\- `help syntax`: explains the syntax of the language.
                    \\- `help words`: provides a list of currently defined words.
                    \\
                , .{});
                return .nothing;
            }

            const argument = arguments[0].string;

            if (eq(argument, "syntax")) {
                // TODO: update the docs once mutliline statements are supported.
                // TODO: improve this. This is too long.
                std.debug.print(
                    \\# Statements
                    \\
                    \\Statements look like this:
                    \\
                    \\    <command expression> <argument expressions>.
                    \\
                    \\Argument expressions are separated from each other with a space character.
                    \\
                    \\Example:
                    \\
                    \\    # This is a comment (not a statement).
                    \\    # Comments are ignored by the interpreter.
                    \\    # Comments start with `#` and span until the end of the line.
                    \\    # The value of this statement is the string `Hello, world!`.
                    \\    => 'Hello, world!'
                    \\
                    \\# Expressions
                    \\
                    \\There are multiple types of expressions: strings literals, blocks and closures.
                    \\
                    \\## String literals
                    \\
                    \\String literals are strings present in code literally. There are two types of string literals: bare strings and quoted strings.
                    \\
                    \\The value of a string literal is the string it represents.
                    \\
                    \\### Bare strings
                    \\
                    \\Bare strings are called bare because they have no special characters in them and therefore can be typed as-is, without quoting.
                    \\
                    \\Examples:
                    \\
                    \\    Hello
                    \\
                    \\### Quoted strings
                    \\
                    \\Quoted strings start and end with a single quote.
                    \\All repeated single quotes are interpreted as a single quote.
                    \\All other characters in the quoted string are interpreted as-is.
                    \\
                    \\Example:
                    \\
                    \\    'John''s pizza'
                    \\
                    \\## Variables
                    \\
                    \\Variables look like strings preceded by `$`.
                    \\
                    \\Example:
                    \\
                    \\    # This statement creates a variable named `x` and sets its value to the string `3`.
                    \\    let x 3
                    \\    # We can refer to this variable now by typing `$x`.
                    \\    => $x
                    \\
                    \\(Under the hood, syntax `$x` gets transformed into `$(get x)`. Therefore, by redefining `get` a custom variable resolver can be installed.)
                    \\
                    \\## Blocks and closures
                    \\
                    \\Blocks and closures are containers of statements.
                    \\
                    \\### Blocks
                    \\
                    \\Blocks execute immediately when seen.
                    \\The value of a block is the value of the last statement in the block.
                    \\
                    \\Example:
                    \\
                    \\    # $(+ 2 3) is a block. It's value is the string 5.
                    \\    + 1 $(+ 2 3)
                    \\
                    \\### Closures
                    \\
                    \\Closures are similar to blocks, but they do not execute immediately.
                    \\
                    \\Example:
                    \\
                    \\    let counter $(
                    \\        # This variable is owned by the current block.
                    \\        let count 0
                    \\        # The value of the block is this closure.
                    \\        => (
                    \\            # Increment the count.
                    \\            set count $(+ $count 1)
                    \\            # Return the updated count.
                    \\            => $count
                    \\        )
                    \\    )
                    \\    # Will return the string 1.
                    \\    counter
                    \\    # Will return the string 2.
                    \\    counter
                    \\
                , .{});
            } else if (eq(argument, "words")) {
                var iterator = self.words.keyIterator();
                while (iterator.next()) |word|
                    std.debug.print("- {s}\n", .{word.*});
            } else {
                std.debug.print("Type `help` for a list of help topics.\n", .{});
            }

            return .nothing;
        } else return error.BuiltinNotDefined,
        .nothing => return error.ValueOfCommandIsNothing,
    }
}

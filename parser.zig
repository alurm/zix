// Not sure if all the errdefers are correct.
// Not sure if the code is correct in general.
// TODO: add tests.
// TODO: pretty print should be usable as {f} from Writer.print.
// I'm not sure if refcounting is enough.

const std = @import("std");

const Tokenizer = @import("tokenizer.zig");

pub const Block = struct {
    ref_count: usize,

    // Not sure if pointers are warranted here.
    statements: []*Statement,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.ref_count -= 1;

        if (self.ref_count == 0) {
            for (self.statements) |statement| {
                statement.deinit(allocator);
                allocator.destroy(statement);
            }
            allocator.free(self.statements);

            // ???
            allocator.destroy(self);
        }
    }

    pub fn parse(
        token_stream: *Tokenizer.Stream,
        allocator: std.mem.Allocator,
    ) (error{
        ReadFailed,
        EndOfStream,
        OutOfMemory,
    } || ParsingError)!*Block {
        var statements: std.ArrayList(*Statement) = .empty;
        errdefer {
            for (statements.items) |item| item.deinit(allocator);
            statements.deinit(allocator);
        }

        while (true) {
            // I'm not sure I like the name "swtch".
            swtch: switch (try token_stream.get(allocator, .peek)) {
                .closing_paren => {
                    (try token_stream.get(allocator, .next)).deinit(allocator);
                    const result = try allocator.create(Block);
                    result.* = .{
                        .statements = try statements.toOwnedSlice(allocator),
                        .ref_count = 1,
                    };
                    return result;
                },
                // I'm not sure if this is correct.
                .newline => {
                    (try token_stream.get(allocator, .next)).deinit(allocator);
                    continue :swtch try token_stream.get(allocator, .peek);
                },
                else => try statements.append(allocator, try Statement.parse(
                    token_stream,
                    allocator,
                )),
            }
        }
    }
};

pub const Expression = union(enum) {
    string: []const u8,
    block: *Block,
    closure: *Block,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |string| allocator.free(string),
            .block, .closure => |block| {
                block.deinit(allocator);
            },
        }
    }
    pub fn parse(
        token_stream: *Tokenizer.Stream,
        allocator: std.mem.Allocator,
    ) !*Expression {
        var got_dollar_sign = false;
        return swtch: switch (try token_stream.get(allocator, .peek)) {
            .dollar_sign => {
                (try token_stream.get(allocator, .next)).deinit(allocator);
                if (got_dollar_sign) return error.DoubleDollarSignToken;
                got_dollar_sign = true;
                continue :swtch try token_stream.get(allocator, .peek);
            },
            .opening_paren => {
                (try token_stream.get(allocator, .next)).deinit(allocator);
                // OwO what's this?
                // const newline = try token_stream.get(allocator, .next);
                // defer newline.deinit(allocator);
                // if (newline != .newline)
                //     return error.ExpectedNewlineTokenAfterOpeningParenToken;
                const block = try Block.parse(token_stream, allocator);
                const result = try allocator.create(Expression);
                result.* = if (got_dollar_sign) .{ .block = block } else .{ .closure = block };
                return result;
            },
            .string => |string| {
                _ = try token_stream.get(allocator, .next);

                // I'm not sure I like this transformation.
                if (got_dollar_sign) {
                    // Transform $x into $(get x).

                    // Not sure all the errdefers are correct.

                    errdefer allocator.free(string);
                    const get_as_string = try allocator.dupe(u8, "get");
                    errdefer allocator.free(get_as_string);
                    const get_e: Expression = .{ .string = get_as_string };
                    const get = try allocator.create(Expression);
                    get.* = get_e;
                    const string_as_expr_e: Expression = .{ .string = string };
                    const string_as_expr = try allocator.create(Expression);
                    string_as_expr.* = string_as_expr_e;
                    var string_array_list: std.ArrayList(*Expression) = .empty;
                    errdefer string_array_list.deinit(allocator);
                    try string_array_list.append(allocator, string_as_expr);
                    const string_slice = try string_array_list.toOwnedSlice(allocator);
                    const stmt_s: Statement = .{
                        .command = get,
                        .arguments = string_slice,
                    };
                    const stmt = try allocator.create(Statement);
                    stmt.* = stmt_s;
                    var stmts_dyn: std.ArrayList(*Statement) = .empty;
                    errdefer stmts_dyn.deinit(allocator);
                    try stmts_dyn.append(allocator, stmt);
                    const stmts = try stmts_dyn.toOwnedSlice(allocator);
                    const block_b: Block = .{
                        .statements = stmts,
                        .ref_count = 1,
                    };
                    const block = try allocator.create(Block);
                    block.* = block_b;
                    const result = try allocator.create(Expression);
                    result.* = .{ .block = block };
                    return result;
                }
                const result = try allocator.create(Expression);
                result.* = .{ .string = string };
                return result;
            },
            else => {
                return error.UnexpectedTokenWhileParsingExpression;
            },
        };
    }

    fn string_needs_quoting(string: []const u8) bool {
        // This part seems error prone.
        // Compare with ./tokenizer.zig:/fn tokenize\(/
        for (string) |c| switch (c) {
            '\n',
            '$',
            '(',
            ')',
            '\\',
            ';',
            ' ',
            '\t',
            '\'',
            '#',
            => return true,
            else => {},
        };
        return string.len == 0;
    }

    pub fn pretty_print(
        self: @This(),
        writer: *std.Io.Writer,
        depth: usize,
    ) error{WriteFailed}!void {
        switch (self) {
            .block, .closure => |it| {
                const long = it.statements.len > 1;
                if (self == .block) try writer.print("$", .{});
                try writer.print("(", .{});
                if (long) try writer.print("\n", .{});
                for (it.statements) |item| {
                    if (long)
                        for (0..depth + 1) |_|
                            try writer.print("\t", .{});
                    try item.pretty_print(writer, depth + 1);
                    if (long) try writer.print("\n", .{});
                }
                if (long)
                    for (0..depth) |_| try writer.print("\t", .{});
                try writer.print(")", .{});
            },
            .string => |string| pretty_print_string(writer, string),
        }
    }
};

// Should be somewhere else
pub fn pretty_print_string(writer: *std.Io.Writer, string: []const u8) !void {
    if (!Expression.string_needs_quoting(string)) {
        try writer.print("{s}", .{string});
        return;
    }
    try writer.print("'", .{});
    for (string) |byte|
        if (byte == '\'') {
            try writer.print("''", .{});
        } else {
            try writer.print("{c}", .{byte});
        };
    try writer.print("'", .{});
}

pub const Statement = struct {
    // Not sure if pointers are warranted here.
    command: *Expression,
    arguments: []*Expression,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.command.deinit(allocator);
        allocator.destroy(self.command);

        for (self.arguments) |argument| {
            argument.deinit(allocator);
            allocator.destroy(argument);
        }

        allocator.free(self.arguments);
    }

    pub fn parse(
        token_stream: *Tokenizer.Stream,
        allocator: std.mem.Allocator,
    ) !*Statement {
        var command: ?*Expression = null;
        var arguments: std.ArrayList(*Expression) = .empty;

        errdefer {
            if (command) |c| c.deinit(allocator);
            for (arguments.items) |item| item.deinit(allocator);
            arguments.deinit(allocator);
        }

        var multiline = false;

        while (true) {
            switch (try token_stream.get(allocator, .peek)) {
                .backslash => {
                    (try token_stream.get(allocator, .next)).deinit(
                        allocator,
                    );
                    // This can be removed, but I'm not sure that is should.
                    if (multiline) return error.BackslashesCanNotNest;
                    multiline = true;
                },
                .semicolon => {
                    (try token_stream.get(allocator, .next)).deinit(
                        allocator,
                    );
                    return if (command) |cmd| {
                        const result = try allocator.create(Statement);
                        result.* = .{
                            .command = cmd,
                            .arguments = try arguments.toOwnedSlice(allocator),
                        };
                        return result;
                    } else {
                        return error.StatementHasNoCommand;
                    };
                },
                // Dunno if this is correct, actually.
                // (
                // )
                // fofof
                // )
                //
                // (Note: I don't know wtf is this comment.)
                // On newline: continue.
                // On a closing paren: we are done.
                inline .newline, .closing_paren => |_, tag| {
                    // We shouldn't consume closing parens.
                    if (tag == .newline) {
                        (try token_stream.get(allocator, .next))
                            .deinit(allocator);
                        if (multiline) continue;
                    }

                    if (command) |cmd| {
                        const result = try allocator.create(Statement);
                        result.* = .{
                            .command = cmd,
                            .arguments = try arguments.toOwnedSlice(
                                allocator,
                            ),
                        };
                        return result;
                    } else continue;
                },
                else => if (command) |_| try arguments.append(allocator, try Expression.parse(
                    token_stream,
                    allocator,
                )) else {
                    command = try Expression.parse(token_stream, allocator);
                },
            }
        }
    }

    pub fn pretty_print(
        self: @This(),
        writer: *std.Io.Writer,
        depth: usize,
    ) !void {
        try self.command.pretty_print(writer, depth);
        for (self.arguments) |argument| {
            try writer.print(" ", .{});
            try argument.pretty_print(writer, depth);
        }
    }
};

const ParsingError = error{
    TokenizerExpectedSpaceAfterPoundSignInComment,
    DoubleDollarSignToken,
    UnexpectedTokenWhileParsingExpression,
    BackslashesCanNotNest,
    StatementHasNoCommand,
    TokenizerExpectedOpeningParenAfterSingleQuote,
};

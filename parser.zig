// Not sure if all the errdefers are correct.
// Not sure if the code is correct in general.

const std = @import("std");

const Tokenizer = @import("tokenizer.zig");

const Block = struct {
    statements: []const Statement,

    pub fn deinit(block: @This(), allocator: std.mem.Allocator) void {
        for (block.statements) |statement| statement.deinit(allocator);
        allocator.free(block.statements);
    }

    pub fn parse(
        token_stream: *Tokenizer.Stream,
        allocator: std.mem.Allocator,
    ) (error{
        ReadFailed,
        EndOfStream,
        OutOfMemory,
    } || ParsingError)!@This() {
        var statements: std.ArrayList(Statement) = .empty;
        errdefer {
            for (statements.items) |item| item.deinit(allocator);
            statements.deinit(allocator);
        }

        while (true) {
            switch (try token_stream.get(allocator, .peek)) {
                .closing_paren => {
                    (try token_stream.get(allocator, .next)).deinit(allocator);
                    return .{ .statements = try statements.toOwnedSlice(allocator) };
                },
                else => try statements.append(allocator, try Statement.parse(
                    token_stream,
                    allocator,
                )),
            }
        }
    }
};

const Expression = union(enum) {
    string: []const u8,
    block: Block,
    closure: Block,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        switch (self) {
            .string => |string| allocator.free(string),
            .block, .closure => |block| block.deinit(allocator),
        }
    }
    pub fn parse(
        token_stream: *Tokenizer.Stream,
        allocator: std.mem.Allocator,
    ) !@This() {
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
                return if (got_dollar_sign) .{ .block = block } else .{ .closure = block };
            },
            .string => |string| {
                _ = try token_stream.get(allocator, .next);

                if (got_dollar_sign) {
                    // Transform $x into $(get x).

                    // Not sure all the errdefers are correct.

                    errdefer allocator.free(string);
                    const get_as_string = try allocator.dupe(u8, "get");
                    errdefer allocator.free(get_as_string);
                    const get: Expression = .{ .string = get_as_string };
                    const string_as_expr: Expression = .{ .string = string };
                    var get_string_dyn: std.ArrayList(Expression) = .empty;
                    errdefer get_string_dyn.deinit(allocator);
                    try get_string_dyn.append(allocator, get);
                    try get_string_dyn.append(allocator, string_as_expr);
                    const get_string = try get_string_dyn.toOwnedSlice(allocator);
                    const stmt: Statement = .{ .expressions = get_string };
                    var stmts_dyn: std.ArrayList(Statement) = .empty;
                    errdefer stmts_dyn.deinit(allocator);
                    try stmts_dyn.append(allocator, stmt);
                    const stmts = try stmts_dyn.toOwnedSlice(allocator);
                    const block: Block = .{ .statements = stmts };
                    return .{ .block = block };
                }
                return .{ .string = string };
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
        return false;
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
            .string => |string| {
                if (!string_needs_quoting(string)) {
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
            },
        }
    }
};

pub const Statement = struct {
    expressions: []const Expression,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        for (self.expressions) |item| item.deinit(allocator);
        allocator.free(self.expressions);
    }

    pub fn parse(
        token_stream: *Tokenizer.Stream,
        allocator: std.mem.Allocator,
    ) !Statement {
        var expressions: std.ArrayList(Expression) = .empty;
        errdefer {
            for (expressions.items) |item| item.deinit(allocator);
            expressions.deinit(allocator);
        }

        while (true) {
            switch (try token_stream.get(allocator, .peek)) {
                inline .newline, .closing_paren => |_, tag| {
                    if (tag == .newline) {
                        (try token_stream.get(allocator, .next)).deinit(allocator);
                        if (expressions.items.len == 0) continue;
                    }
                    return .{
                        .expressions = try expressions.toOwnedSlice(allocator),
                    };
                },
                else => try expressions.append(allocator, try Expression.parse(
                    token_stream,
                    allocator,
                )),
            }
        }
    }

    pub fn pretty_print(
        self: @This(),
        writer: *std.Io.Writer,
        depth: usize,
    ) !void {
        for (self.expressions, 0..) |e, i| {
            if (i != 0) try writer.print(" ", .{});
            try e.pretty_print(writer, depth);
        }
    }
};

const ParsingError = error{
    TokenizerExpectedSpaceAfterPoundSignInComment,
    DoubleDollarSignToken,
    UnexpectedTokenWhileParsingExpression,
};

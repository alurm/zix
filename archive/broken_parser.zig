const std = @import("std");
const ArrayList = std.ArrayList;

const Token = @import("tokenizer.zig").Token;

const Self = @This();

// NOTE: ZLS setup seems to be not quite right.
// Same diagnostics are shown multiple times (three times, actually).

// Maybe just regular functions can be used?
// There still needs to be a stack somewhere.
// But maybe it's not necessary to be required.

const BlockContext = struct {};
const StatementContext = struct {};
const ExpressionContext = struct {};

// const Context = struct {
//     type: union(enum) {
//         expression: ExpressionContext,
//         statement: StatementContext,
//         block: BlockContext,
//     },
//     done: bool,
// };

// const Statement = []const Expression;
// const Expression = union(enum) {
//     string: []const u8,
//     closure: Group,
//     block: Group,
// };

pub const Expression = struct {
    pub const Parser = union(enum) {
        checking_for_dollar_sign,
    };

    // pub fn parse(parser: *Parser, allocator: std.mem.Allocator, token: Token) !void {
    //     switch (parser) {}
    //     _ = allocator;
    //     _ = token;
    // }
};

pub const Group = struct {
    pub const Parser = void;
};

pub const Statement = struct {
    const Out = union(enum) {
        @"return": []Expression,
        call: Expression.Parser,
    };

    pub const Parser = struct {
        expressions: ArrayList(Expression),
        context: ?*Group.Parser,
    };

    pub fn parse(parser: *Parser, allocator: std.mem.Allocator, token: Token) !Out {
        if (token == .closing_paren) {
            return .{ .@"return" = try parser.expressions.toOwnedSlice(allocator) };
        }
        return .{ .call = .checking_for_dollar_sign };
    }
};

pub const Current = union(enum) {
    expression: Expression.Parser,
    statement: Statement.Parser,
};

pub const Frame = struct {
    frame: ?*Frame,
    content: union(enum) {
        done: union(enum) {},
        in_progress: union(enum) {},
    },
};

pub fn dispatch(frame: *Frame, token: Token) !void {
    switch (frame.*.content) {}
}

pub fn parse(current: *Current, allocator: std.mem.Allocator, token: Token) !void {
    switch (current.*) {
        .statement => |*statement| {
            switch (try Statement.parse(statement, allocator, token)) {
                .call => {
                    // continue :swtch
                },
                .@"return" => {},
            }
        },
        .expression => {},
    }
}

// fn group(parser: *GroupParser, allocator: std.mem.Allocator, token: Token) !void {
//     if (token == .closing_paren) {
//         return;
//     }
//     _ = allocator;
// }

// fn parse(ctx: *Context, allocator: std.mem.Allocator, token: Token) void {
//     switch (ctx.type) {
//         // .expression => {},
//         // .statement => {},
//         .block => {},
//     }
//     _ = allocator;
//     _ = token;
// }

// context: Context,

// // TODO: how to produce a result?
// const Expression = union(enum) {
//     check_for_dollar_sign,
//     check_for_opening_paren,
//     expect_newline,
//     // ???
// };

// // ???
// fn expression() {
// }

// THE PREVIOUS ATTEMPT

// const Statement = []const Expression;
// const Expression = union(enum) {
//     string: []const u8,
//     closure: []const Statement,
//     block: []const Statement,
// };

// const Statement = ArrayList(Expression);
// const Expression = union(enum) {
//     string: []u8,
//     closure: ArrayList(Statement),
//     block: ArrayList(Statement),
// };

// FIXME this seems incorrect.
// We should know statically that a regular_statement_part is inside of a regular_statement.
//
// pub const Context = struct {
//     context: ?*Context,
//     state: union(enum) {
//         // regular_statements, // : ArrayList(Statement),
//         regular_statement: Statement,
//         regular_statement_part: union(enum) {
//             check_for_dollar_sign,
//             check_for_opening_paren: enum {
//                 dollared,
//                 not_dollared,
//             },
//             expect_newline,
//         },
//     },
// };

// TODO: order of declaration in files (in all of them) in unclear.
// ZLS doesn't seem to be helpful here.
// Fix that.

// TODO: should this be optional?
// context: *Context

// pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
//     var context: ?*Context = self.context;
//     while (context) |c| {
//         const up = c.context;
//         allocator.destroy(c);
//         context = up;
//     }
// }

// Should be in sync with `./grammar.md`.
//
// # First attempt, greately simplified:
// - $foo is not handled.
// - (foo bar) is not treated specially.
// - \\ is not handled.
//
// TODO: it's not clear what to do with the imaginary <end of input>.
// We can consider emitting it, but I'm not sure if that's a good idea.
// Seems like there are alternative ways.
// To compare, requiring files to end with a newline might be too much.
// But this is also not clear.
//
// pub fn parse_subset(self: *Self, allocator: std.mem.Allocator, token: Token) !void {
//     // Throw out all the comments we don't care about for now.
//     switch (token) {
//         .comment, .backslash, .semicolon => return {},
//         else => {},
//     }

//     return switch (self.context.state) {
//         .regular_statement => switch (token) {
//             .newline => {},
//             else => {
//                 const context = self.context;
//                 self.context = try allocator.create(Context);
//                 self.context.* = .{
//                     .context = context,
//                     .state = .{ .regular_statement_part = .check_for_dollar_sign },
//                 };
//             },
//         },
//         .regular_statement_part => |*regular_statement_part| switch (regular_statement_part.*) {
//             .check_for_dollar_sign => switch (token) {
//                 .dollar_sign => {
//                     regular_statement_part.* = .{ .check_for_opening_paren = .dollared };
//                 },
//                 .opening_paren => regular_statement_part.* = .expect_newline,
//                 .string => |string| {},
//             },
//             else => @panic("fuck"),
//         },
//         // .regular_statement_part => @panic("todo"),
//         // .regular_statements => switch (token) {
//         //     .closing_paren => {
//         //         // FIXME.
//         //         try allocator.destroy(self.context);
//         //         self.context = self.context.context.?;
//         //     },
//         // },
//     };
// }

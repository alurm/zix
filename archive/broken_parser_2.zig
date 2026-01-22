// Perhaps, instead of processing one token at a time,
// it would be better to pull tokens on demand.
//
// That would make it possible to write a recursive descent parser.
// That would be easy, but that would also make the parser crash on highly nested inputs.
//
// Seems like many popular languages crash on hightly nested inputs anyway.
//
// That includes the reference implementation of Lua, a data description language.
//
// On the other hand, perhaps there is a way to make this work, one token at a time.
//
// On the other hand, perhaps pulling tokens doesn't imply a stack-overflowing implementation.

// Fuck this shit, I'm out.

const std = @import("std");

const Token = @import("tokenizer.zig").Token;

pub const Statement = struct {
    pub const Parser = union(enum) { called_expression_parser };
};

pub const Block = struct {
    pub const Result = []Statement.Result;

    pub const Parser = std.ArrayList(Statement.Result);

    fn parse(
        parser: *Block.Parser,
        allocator: std.mem.Allocator,
        token: Token,
    ) !?Block.Result {
        if (token == .closing_paren) return parser.toOwnedSlice(allocator);
        return null;
    }
};

pub const Parser = struct {
    const Self = @This();

    const State = union(enum) {
        block: Block.Parser,
    };

    up: ?*Self,
    state: State,

    fn parse(self: *Self, allocator: std.mem.Allocator, token: Token) void {
        switch (self.state) {
            .block => |*block| {
                if (Block.parse(block, allocator, token)) |_| {}
            },
        }
    }
};

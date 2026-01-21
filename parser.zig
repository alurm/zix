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

const Token = @import("tokenizer.zig").Token;

const Parser = struct {
    const Self = @This();

    fn parse(self: *Self, token: Token) void {
        _ = token;
        _ = self;
    }
};

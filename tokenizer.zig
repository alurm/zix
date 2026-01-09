//! A tokenizer for the language.
//!
//! The Token type defines the token.
//!
//! tokenize is the primary function which operates one byte at a time to support incremental parsing.
//!
//! .deinit(...) should be called to deinit an object of this type.

// TODO: add more documentation comments.
// TODO: add tests.
// TODO: think how this should be tested properly.
// TODO: does Zig have a way to show test coverage?
// https://www.google.com/search?q=zig+test+coverage
// https://github.com/ziglang/zig/issues/352, "Support code coverage when testing".

const std = @import("std");
const Self = @This();

// We accumulate results as ArrayLists and turn them into slices when done.
state: union(enum) {
    default,
    comment: struct {
        value: std.ArrayList(u8),
        state: union(enum) {
            expecting_space,
            after_space,
        } = .expecting_space,
    },
    bare_word: std.ArrayList(u8),
    quoted_word: struct {
        value: std.ArrayList(u8),
        state: union(enum) {
            default,
            /// After a single quote (not the first one).
            after_quote,
        } = .default,
    },
} = .default,

// TODO: consider storing source location in the tokens.
// Or find some other way to do better error reporting.
/// .deinit(...) should be called to deinit an object of this type.
pub const Token = union(enum) {
    backslash,
    semicolon,

    opening_paren,
    closing_paren,

    dollar_sign,

    // Newlines are emitted since some code may be rejected based on that later.
    newline,

    word: []u8,
    comment: []u8,

    pub fn deinit(self: Token, allocator: std.mem.Allocator) void {
        switch (self) {
            .newline,
            .semicolon,
            .backslash,
            .opening_paren,
            .closing_paren,
            .dollar_sign,
            => {},

            .word,
            .comment,
            => |it| allocator.free(it),
        }
    }

    // TODO: stop using std.debug.print.
    // This function is kinda crappy but works.
    /// Prints a line to stderr describing the given token using std.debug.print.
    pub fn print(token: Token) void {
        switch (token) {
            inline .backslash,
            .closing_paren,
            .dollar_sign,
            .newline,
            .opening_paren,
            .semicolon,
            => |_, tag| std.debug.print("{s}\n", .{@tagName(tag)}),
            inline .comment, .word => |value, tag| std.debug.print("{s}: {s}\n", .{ @tagName(tag), value }),
        }
    }
};

// Not sure if this naming is the best.
/// Tokenizes a whole string instead of a single byte.
pub fn string(tokenizer: *Self, allocator: std.mem.Allocator, str: []const u8) ![]Token {
    var result: std.ArrayList(Token) = .empty;
    for (str) |char| {
        const tokens = try tokenizer.tokenize(allocator, char);
        for (tokens) |token| try result.append(allocator, token);
        allocator.free(tokens);
    }
    return result.toOwnedSlice(allocator);
}

// TODO: perhaps it would be sensible end by setting self.* to undefined here?
pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    switch (self.state) {
        .default => {},
        .bare_word => |*list| list.deinit(allocator),
        inline .comment, .quoted_word => |*data| data.value.deinit(allocator),
    }
}

// A wrapper to call .toOwnedSlice on the result of tokenize_main.
/// Tokenizes one character of input.
pub fn tokenize(self: *Self, allocator: std.mem.Allocator, char: u8) ![]Token {
    var result = try tokenizeMain(self, allocator, char);
    return result.toOwnedSlice(allocator);
}

// TODO: consider recognizing an end of file special character.
// This is not required if we require chunks to end with newlines.
// But I'm not sure that this is a reasonable requirement.
//
// TODO: consider rejecting some funny characters right off the bat.
fn tokenizeMain(tokenizer: *Self, allocator: std.mem.Allocator, char: u8) !std.ArrayList(Token) {
    var result: std.ArrayList(Token) = .empty;
    errdefer result.deinit(allocator);

    swich: switch (tokenizer.state) {
        .comment => |*comment| switch (comment.state) {
            .expecting_space => switch (char) {
                ' ' => comment.state = .after_space,
                // TODO: turn this into a more useful error message.
                else => return error.TokenizerExpectedSpaceAfterPoundSignInComment,
            },
            .after_space => switch (char) {
                '\n' => {
                    try result.append(
                        allocator,
                        .{ .comment = try comment.value.toOwnedSlice(allocator) },
                    );
                    tokenizer.state = .default;
                },
                else => try comment.value.append(allocator, char),
            },
        },
        .default => switch (char) {
            ' ', '\t' => {},
            inline '\n', '$', '(', ')', '\\', ';' => |c| {
                try result.append(allocator, switch (c) {
                    '\n' => .newline,
                    '$' => .dollar_sign,
                    '(' => .opening_paren,
                    ')' => .closing_paren,
                    '\\' => .backslash,
                    ';' => .semicolon,
                    else => comptime unreachable,
                });
            },
            '#' => tokenizer.state = .{
                .comment = .{ .value = .empty, .state = .expecting_space },
            },
            '\'' => tokenizer.state = .{ .quoted_word = .{ .value = .empty } },
            // NOTE: could be useful to reject some funny characters here, which we currently don't do.
            else => {
                tokenizer.state = .{ .bare_word = .empty };
                try tokenizer.state.bare_word.append(allocator, char);
            },
        },
        // Inside of quotes, a double single quote is treated as a literal single quote.
        // No other escape sequences are available.
        .quoted_word => |*quoted_word| switch (quoted_word.state) {
            .default => switch (char) {
                '\'' => quoted_word.state = .after_quote,
                else => try quoted_word.value.append(allocator, char),
            },
            .after_quote => switch (char) {
                '\'' => {
                    quoted_word.state = .default;
                    try quoted_word.value.append(allocator, '\'');
                },
                else => {
                    try result.append(allocator, .{
                        .word = try quoted_word.value.toOwnedSlice(allocator),
                    });
                    // Analyze the current char again in the default state.
                    tokenizer.state = .default;
                    continue :swich tokenizer.state;
                },
            },
        },

        // It can be possible to complicate this algorithm.
        // It would be nice to be able to paste raw URLs without using quotes.
        // Some of them have parens.
        // One way to solve this would be to accept matching parens.
        // E.g. to tokenize https://foo.com/(bar) as a bare word.
        // This might require arbitrary lookahead.
        // Never stopping at ')' is undesirable because then in (foo bar baz),
        // 'baz)' would be a bare word.
        // For now, just stop if ')' is found.
        .bare_word => |*bare_word| switch (char) {
            ' ', '\t', '\n', ')' => {
                try result.append(allocator, .{
                    .word = try bare_word.toOwnedSlice(allocator),
                });
                // Analyze the current char again in the default state.
                tokenizer.state = .default;
                continue :swich tokenizer.state;
            },
            else => try bare_word.append(allocator, char),
        },
    }

    return result;
}

test {
    const a_token: Token = .{ .word = try std.testing.allocator.alloc(u8, 100) };
    defer std.testing.allocator.free(a_token.word);
}

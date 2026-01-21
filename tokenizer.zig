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
const testing = std.testing;

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
    bare_string: std.ArrayList(u8),
    quoted_string: struct {
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

    string: []const u8,
    comment: []const u8,

    pub fn deinit(self: Token, allocator: std.mem.Allocator) void {
        switch (self) {
            .newline,
            .semicolon,
            .backslash,
            .opening_paren,
            .closing_paren,
            .dollar_sign,
            => {},

            .string,
            .comment,
            => |it| allocator.free(it),
        }
    }

    // TODO: stop using std.debug.print.
    // This function is kinda crappy but works.
    /// Prints a line to stderr describing the given token using std.debug.print.
    pub fn print(token: Token, writer: *std.Io.Writer) !void {
        return switch (token) {
            inline .backslash,
            .closing_paren,
            .dollar_sign,
            .newline,
            .opening_paren,
            .semicolon,
            => |_, tag| writer.print("{s}\n", .{@tagName(tag)}),
            inline .comment, .string => |value, tag| writer.print("{s}: {s}\n", .{ @tagName(tag), value }),
        };
    }
};

// Not sure if this naming is the best.
// Might be buggy?
// I don't know.
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
        .bare_string => |*list| list.deinit(allocator),
        inline .comment, .quoted_string => |*data| data.value.deinit(allocator),
    }
}

// A wrapper to call .toOwnedSlice on the result of tokenize_main.
// Does toOwnedSlice free on error?
/// Tokenizes one character of input.
pub fn tokenize(self: *Self, allocator: std.mem.Allocator, char: u8) ![]Token {
    var result = try tokenizeMain(self, allocator, char);
    return result.toOwnedSlice(allocator);
}

pub const Stream = struct {
    buffer: []Token,
    position: usize,
    reader: *std.Io.Reader,
    tokenizer: *Self,

    pub fn init(reader: *std.Io.Reader, tokenizer: *Self) @This() {
        return .{
            .buffer = &[0]Token{},
            .reader = reader,
            .position = 0,
            .tokenizer = tokenizer,
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        // Only free tokens not already consumed.
        for (self.buffer[self.position..self.buffer.len]) |token| token.deinit(allocator);
        allocator.free(self.buffer);
    }

    pub fn peek_buffer(self: *@This()) ?Token {
        if (self.position < self.buffer.len) {
            const token = self.buffer[self.position];
            return token;
        }
        return null;
    }

    // Seems terribly inefficient.
    pub fn get(self: *@This(), allocator: std.mem.Allocator, mode: enum {
        peek,
        next,
    }) !Token {
        swtch: switch (self.position < self.buffer.len) {
            true => {
                const token = self.buffer[self.position];
                if (mode == .next) self.position += 1;
                return token;
            },
            false => {
                allocator.free(self.buffer);
                self.buffer.len = 0;
                self.position = 0;
                var byte: [1]u8 = undefined;
                try self.reader.readSliceAll(&byte);
                self.buffer = try self.tokenizer.tokenize(allocator, byte[0]);
                continue :swtch self.position < self.buffer.len;
            },
        }
    }
};

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
                    // Without this just removing all the comment tokens might change the meaning.
                    try result.append(allocator, .newline);
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
            '\'' => tokenizer.state = .{ .quoted_string = .{ .value = .empty } },
            // NOTE: could be useful to reject some funny characters here, which we currently don't do.
            else => {
                tokenizer.state = .{ .bare_string = .empty };
                try tokenizer.state.bare_string.append(allocator, char);
            },
        },
        // Inside of quotes, a double single quote is treated as a literal single quote.
        // No other escape sequences are available.
        .quoted_string => |*quoted_string| switch (quoted_string.state) {
            .default => switch (char) {
                '\'' => quoted_string.state = .after_quote,
                else => try quoted_string.value.append(allocator, char),
            },
            .after_quote => switch (char) {
                '\'' => {
                    quoted_string.state = .default;
                    try quoted_string.value.append(allocator, '\'');
                },
                else => {
                    try result.append(allocator, .{
                        .string = try quoted_string.value.toOwnedSlice(allocator),
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
        // E.g. to tokenize https://foo.com/(bar) as a string.
        // This might require arbitrary lookahead.
        // Never stopping at ')' is undesirable because then in (foo bar baz),
        // 'baz)' would be a string.
        // For now, just stop if ')' is found.
        .bare_string => |*bare_string| switch (char) {
            ' ', '\t', '\n', ')' => {
                try result.append(allocator, .{
                    .string = try bare_string.toOwnedSlice(allocator),
                });
                // Analyze the current char again in the default state.
                tokenizer.state = .default;
                continue :swich tokenizer.state;
            },
            else => try bare_string.append(allocator, char),
        },
    }

    return result;
}

// TODO: consider removing this test.
test {
    const a_token: Token = .{ .string = try std.testing.allocator.alloc(u8, 100) };
    defer std.testing.allocator.free(a_token.string);
}

test "tokenize an empty string" {
    var tokenizer: Self = .{};
    defer tokenizer.deinit(testing.allocator);
    const tokens = try tokenizer.string(testing.allocator, "");
    defer testing.allocator.free(tokens);
    defer for (tokens) |token| token.deinit(testing.allocator);
    try testing.expect(tokens.len == 0);
}

test "tokenize a bunch of stuff" {
    var tokenizer: Self = .{};
    defer tokenizer.deinit(testing.allocator);

    const str =
        \\$ 'hello' world (very cool) # This is a comment.
        \\\
        \\  hello world
        \\;
        \\
    ;
    const tokens = try tokenizer.string(
        testing.allocator,
        str,
    );
    defer testing.allocator.free(tokens);
    defer for (tokens) |token| token.deinit(testing.allocator);

    try testing.expectEqualDeep(
        tokens,
        @as([]const Token, &.{
            .{ .dollar_sign = {} },
            .{ .string = "hello" },
            .{ .string = "world" },
            .{ .opening_paren = {} },
            .{ .string = "very" },
            .{ .string = "cool" },
            .{ .closing_paren = {} },
            .{ .comment = "This is a comment." },
            .{ .newline = {} },
            .{ .backslash = {} },
            .{ .newline = {} },
            .{ .string = "hello" },
            .{ .string = "world" },
            .{ .newline = {} },
            .{ .semicolon = {} },
            .{ .newline = {} },
        }),
    );
}

test "tokenize trailing space" {
    var tokenizer: Self = .{};
    defer tokenizer.deinit(testing.allocator);
    const tokens = try tokenizer.tokenize(testing.allocator, ' ');
    defer testing.allocator.free(tokens);
    defer for (tokens) |token| token.deinit(testing.allocator);
}

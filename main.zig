// I'm not sure if I understand how the module system works in terms of laziness.
// Maybe something like comptime { _ = ... } can be useful.

const std = @import("std");
const root = @import("zix");

const Tokenizer = root.Tokenizer;

pub fn main() !void {
    // TODO: pick an allocator based on the current build configuration.
    // const allocator = std.heap.smp_allocator;
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    // TODO: should be a test.
    {
        var tokenizer: Tokenizer = .{};
        std.debug.assert((try tokenizer.tokenize(allocator, ' ')).len == 0);

        const dollar_sign_singleton = try tokenizer.tokenize(allocator, '$');
        std.debug.assert(dollar_sign_singleton.len == 1);
        defer allocator.free(dollar_sign_singleton);
    }

    // TODO: should be a test.
    {
        var tokenizer: Tokenizer = .{};
        defer tokenizer.deinit(allocator);

        const string =
            \\$ 'hello' world (very cool) # This is a comment.
            \\\
            \\  hello world
            \\;
            \\
        ;
        const tokens = try tokenizer.string(
            allocator,
            string,
        );
        defer allocator.free(tokens);
        defer for (tokens) |token| token.deinit(allocator);

        std.debug.print("# Input string\n\n{s}\n# Tokens\n\n", .{string});
        for (tokens) |token| token.print();
    }
}

// TODO: understand what in the world is this.
// https://ziggit.dev/t/how-do-i-get-zig-build-to-run-all-the-tests/4434
// Makes tests from other files run on zig test main.zig.
// Perhaps can be removed when the Zig build system is used more extensively.
// I don't know.
test {
    std.testing.refAllDecls(@This());
}

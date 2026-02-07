// THis is a faking mess we have too many shit everywhere
// this is a static variable situation
// i think or not idk
// this is not lib/shell, this is wasm shit
// or not. fak it
// or yes. fak you!
// useles comments
// remove wasm allocator i beg for easy
// remove faking catch unreachable.
// dont require newline at end perhaps

const std = @import("std");
const Environment = @import("environment.zig");
const Tokenizer = @import("tokenizer.zig");
const allocator = std.heap.wasm_allocator;
const parser = @import("parser.zig");

// Deinit when. Neva sak ma dik.
// shit shit shit
var env: Environment = undefined;
var init = false;

pub fn doString(input: []u8) []u8 {
    const Shit = struct {
        var shit = std.Io.Writer.failing;
    };
    if (!init) {
        init = true;
        // what the fak.
        env = Environment.default(allocator, &Shit.shit) catch unreachable;
    }
    var reader: std.Io.Reader = .fixed(input);
    var writer_object: std.Io.Writer.Allocating = .init(allocator);
    var writer = &writer_object.writer;

    // what fak
    env.writer = writer;

    var tokenizer: Tokenizer = .{};
    defer tokenizer.deinit(allocator);

    var token_stream: Tokenizer.Stream = .init(&reader, &tokenizer);

    const block = parser.Block.parse(&token_stream, allocator) catch unreachable;
    defer block.deinit(allocator);

    const handle = env.evaluate_block(allocator, block, &.{}) catch unreachable;
    defer env.gc.unprotect(handle);
    // const value = G.env.gc.get(handle);

    // hm cond in browser toggle?

    writer.print("{f}\n", .{env.gc.get(handle)}) catch unreachable;
    // writer.flush();

    return writer_object.toOwnedSlice() catch unreachable;
}

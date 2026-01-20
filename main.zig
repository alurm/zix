const std = @import("std");

const root = @import("zix");
const Tokenizer = root.Tokenizer;

// The current idea is to always go through root for everything.

// TODO: figure out this value.
// Also, is there some potential issue where this value is important?
// I.e. they have to correspond on both the writer's and reader's sites?
// I'm not sure.
//
// TODO: should arrays of such size be allocated on the stack?
const buffer_size = 1024;

fn loop(allocator: std.mem.Allocator, tokenizer: *Tokenizer) !void {
    var writer_buffer: [buffer_size]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&writer_buffer);
    const write = &writer.interface;

    var reader_buffer: [buffer_size]u8 = undefined;
    var reader = std.fs.File.stdin().reader(&reader_buffer);
    var read = &reader.interface;

    while (true) {
        var read_buffer: [buffer_size]u8 = undefined;
        // Needed since reader.readVec accepts a [][]u8.
        var read_buffers: [1][]u8 = .{&read_buffer};

        // Perhaps we can handle WriteFailed somehow, unclear.
        defer write.flush() catch {};

        const n = read.readVec(&read_buffers) catch |e| switch (e) {
            // Not sure when this can happen.
            error.ReadFailed => return e,
            error.EndOfStream => return,
        };

        // Not completely sure about this.
        // For some reason, .readVec seems to be returning 0 as the first read.
        if (n == 0) continue;

        for (read_buffer[0..n]) |c| {
            const tokens = try tokenizer.tokenize(allocator, c);
            defer allocator.free(tokens);
            for (tokens) |token| {
                defer token.deinit(allocator);
                token.print();
            }
        }

        // A heuristic, doesn't always work.
        // With a complete parser, we can try to be more smart.
        try write.print("\n", .{});
    }
}

pub fn main() !void {
    // TODO: pick an allocator based on the current build configuration.
    // const allocator = std.heap.smp_allocator;
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var tokenizer: Tokenizer = .{};
    defer tokenizer.deinit(allocator);

    try loop(allocator, &tokenizer);
}

// Do we need test { std.testing.refAllDecls(@This()); }?
// Or comptime { _ = ... }?
// Perhaps can be?
// Perhaps referencing stuff manually would be enough?
// I don't know.
// https://ziggit.dev/t/how-do-i-get-zig-build-to-run-all-the-tests/4434
// Move top faken hidden imports.
// Fixing naming of faking files.

const std = @import("std");

const Gc = @import("gc.zig");
const builtins = @import("builtins.zig");
const Environment = @import("environment.zig");
const parser = @import("parser.zig");
const Tokenizer = @import("tokenizer.zig");

test {
    std.testing.refAllDecls(@This());
}

// The current idea is to always go through root for everything.

// TODO: figure out this value.
// Also, is there some potential issue where this value is important?
// I.e. they have to correspond on both the writer's and reader's sites?
// I'm not sure.
//
// TODO: should arrays of such size be allocated on the stack?
const buffer_size = 1024;

// TODO: remove this.
fn loop(allocator: std.mem.Allocator, tokenizer: *Tokenizer) !void {
    var reader_buffer: [buffer_size]u8 = undefined;
    var reader = std.fs.File.stdin().reader(&reader_buffer);
    const read = &reader.interface;

    var writer_buffer: [buffer_size]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&writer_buffer);
    const write = &writer.interface;

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
                try token.print(write);
            }
        }

        // A heuristic, doesn't always work.
        // With a complete parser, we can try to be more smart.
        try write.print("\n", .{});
    }
}

pub fn help(writer: *std.Io.Writer) !void {
    return writer.print(
        \\Zix 0.0.1
        \\
        \\To exit, type `)`.
        \\To get help, type `help`.
        \\To start Zix in batch mode: `zix < program.zix`.
        \\To start Zix in interactive mode: `zix [<files>...]`. Files are evaluated before a prompt is shown.
        \\
    , .{});
}

// Or something like that.
pub fn main() !void {
    // TODO: pick an allocator based on the current build configuration.
    // const allocator = std.heap.smp_allocator;
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var tokenizer: Tokenizer = .{};
    defer tokenizer.deinit(allocator);

    // try loop(allocator, &tokenizer);

    var reader_buffer: [buffer_size]u8 = undefined;
    var reader = std.fs.File.stdin().reader(&reader_buffer);
    const read = &reader.interface;

    var writer_buffer: [buffer_size]u8 = undefined;
    var writer = std.fs.File.stdout().writer(&writer_buffer);
    const write = &writer.interface;

    try shell(write, read, &tokenizer, allocator);
}

// This is kinda awkward.
pub const std_options: std.Options = .{
    .fmt_max_depth = 10,
};

// C is evil?
fn isInteractive() bool {
    return std.c.isatty(std.c.STDIN_FILENO) == 1;
}

fn shell(
    writer: *std.Io.Writer,
    reader: *std.Io.Reader,
    tokenizer: *Tokenizer,
    allocator: std.mem.Allocator,
) !void {
    var token_stream: Tokenizer.Stream = .init(reader, tokenizer);
    defer token_stream.deinit(allocator);

    var env: Environment = try .default(allocator, writer);

    // This is bad. Is it. Idk.
    defer env.deinit(allocator) catch unreachable;

    try if (isInteractive()) interactive(
        writer,
        allocator,
        &token_stream,
        &env,
    ) else nonInteractive(
        writer,
        allocator,
        &token_stream,
        &env,
        .print,
    );
}

// TODO: get rid of this?
// Dedup.
fn nonInteractive(
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    token_stream: *Tokenizer.Stream,
    env: *Environment,
    // This is a hack.
    mode: enum { print, silent },
) !void {
    var block = try parser.Block.parse(
        token_stream,
        allocator,
    );
    defer block.deinit(allocator);

    const handle = try env.evaluate_block(
        allocator,
        block,
    );
    defer env.gc.unprotect(handle);
    // Hacky?
    const value = env.gc.get(handle);
    if (mode == .print and value.* != .nothing) {
        try writer.print("{f}\n", .{env.gc.get(handle)});
        try writer.flush();
    }
}

fn interactive(
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    token_stream: *Tokenizer.Stream,
    env: *Environment,
) !void {
    try help(writer);

    // Don't just do 1..! It's rude. OwO.
    for (std.os.argv[1..]) |path_z| {
        // std.debug.print("path: {s}\n", .{path_z});

        const path = std.mem.sliceTo(path_z, 0);

        var reader_buffer: [buffer_size]u8 = undefined;
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        defer file.close();

        var reader_object = std.fs.File.reader(file, &reader_buffer);
        const reader = &reader_object.interface;

        var tokenizer: Tokenizer = .{};
        defer tokenizer.deinit(allocator);

        var file_token_stream: Tokenizer.Stream = .init(reader, &tokenizer);
        defer file_token_stream.deinit(allocator);

        var block = try parser.Block.parse(
            &file_token_stream,
            allocator,
        );
        defer block.deinit(allocator);

        env.gc.unprotect(try env.evaluate_block(allocator, block));
    }

    while (true) {
        try writer.print("\n", .{});
        try writer.flush();

        // Not sure if this should be before or after parsing.
        {
            const token = token_stream.get(allocator, .peek) catch |e| switch (e) {
                error.EndOfStream => return,
                else => return e,
            };
            if (token == .closing_paren) return;
        }

        var statement = try parser.Statement.parse(
            token_stream,
            allocator,
        );
        defer allocator.destroy(statement);
        defer statement.deinit(allocator);

        // try write.print("{any}\n", .{statement});

        // TODO: improve printing.
        // TODO: check that $'foo' works.
        // TODO: implement custom `get`.
        // TODO: don't panic out of bounds in builtins.
        // TODO: detect leaks.

        const handle = env.evaluate_statement(
            allocator,
            statement,
        ) catch |err| switch (err) {
            // Bad code?
            error.ValueOfCommandIsContext,
            error.BadArgumentCount,
            error.WordNotDefined,
            error.BadArgumentType,
            error.ValueOfCommandIsString,
            error.ValueOfCommandIsNothing,
            error.ExpressionTypeNotImplemented,
            error.CommandNotFound,
            => {
                try writer.print("{}\n", .{err});
                continue;
            },

            else => return err,
        };
        defer env.gc.unprotect(handle);

        const value = env.gc.get(handle);

        if (value.* != .nothing) {
            try writer.print("{f}\n", .{env.gc.get(handle)});
            try writer.flush();
        }

        // const Gc = @import("gc.zig");
        // var gc: Gc = .init(.default);
        // defer gc.deinit(allocator);
        // _ = try gc.alloc(allocator, .nothing, .unprotected);
        // _ = try gc.alloc(allocator, .nothing, .unprotected);
        // _ = try gc.alloc(allocator, .nothing, .unprotected);
        // _ = try gc.alloc(allocator, .nothing, .unprotected);
        // _ = try gc.alloc(allocator, .nothing, .unprotected);
        // _ = try gc.alloc(allocator, .nothing, .unprotected);
    }
}

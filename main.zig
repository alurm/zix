// Do we need test { std.testing.refAllDecls(@This()); }?
// Or comptime { _ = ... }?
// Perhaps can be?
// Perhaps referencing stuff manually would be enough?
// I don't know.
// https://ziggit.dev/t/how-do-i-get-zig-build-to-run-all-the-tests/4434

const std = @import("std");

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
        \\To exit, type `)` (without backticks) followed by a newline.
        \\
        \\For help, type `help` (without backticks) followed by a newline.
        \\
    , .{});
}

// Write should be renamed as writer.
// Read should be renamed as reader.
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

fn shell(
    write: *std.Io.Writer,
    read: *std.Io.Reader,
    tokenizer: *Tokenizer,
    allocator: std.mem.Allocator,
) !void {
    var token_stream: Tokenizer.Stream = .init(read, tokenizer);
    defer token_stream.deinit(allocator);

    try help(write);

    var env: Environment = try .init(allocator);

    // This is bad.
    defer env.deinit(allocator) catch unreachable;

    // This (including defers is a mess).
    // Shouldn't be here.
    // Also, env.deinit should do more? Or less? I don't know.
    // Bad mess.
    {
        const builtins = @import("builtins.zig");

        const decls = @typeInfo(builtins).@"struct".decls;

        comptime var array: [decls.len]struct {
            name: []const u8,
            value: builtins.Builtin,
        } = undefined;

        inline for (decls, 0..) |decl, i| {
            const name = decl.name;
            const field = @field(builtins, name);
            switch (@typeInfo(@TypeOf(field))) {
                .@"fn" => array[i] = .{ .name = name, .value = field },
                else => {},
            }
        }

        const Gc = @import("gc.zig");

        var handles: [decls.len]Gc.Handle = undefined;

        // OOM is not handled here.

        for (array, 0..) |builtin, i| {
            // > unprotected
            // Shouldn't be an issue if we immediately put it into context.
            // Which we do.
            const handle = try env.gc.alloc(
                allocator,
                .{ .builtin = builtin.value },
                .unprotected,
            );

            handles[i] = handle;

            const context = &env.gc.get(env.context).context;

            try context.words.put(
                allocator,
                try allocator.dupe(u8, builtin.name),
                handle,
            );
        }

        // break :blk handles;
    }

    while (true) {
        try write.print("\n", .{});
        try write.flush();

        // Not sure if this should be before or after parsing.
        {
            const token = token_stream.get(allocator, .peek) catch |e| switch (e) {
                error.EndOfStream => return,
                else => return e,
            };
            if (token == .closing_paren) return;
        }

        var statement = try parser.Statement.parse(
            &token_stream,
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
            error.BadArgumentCount,
            error.WordNotDefined,
            error.BadArgumentType,
            error.ValueOfCommandIsString,
            error.ValueOfCommandIsNothing,
            error.ExpressionTypeNotImplemented,
            error.CommandNotFound,
            => {
                try write.print("{}\n", .{err});
                continue;
            },

            else => return err,
        };
        defer env.gc.unprotect(handle);

        try write.print("{f}\n", .{env.gc.get(handle)});

        try write.flush();

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

// # Wanted builtins
//
// - set
// - cat, ..
// - del?
// - help, help system
// - read file?
// - unix
// - same?
// - 'same strings?'
// - string is?
// - while
// - list?

const std = @import("std");

const Environment = @import("environment.zig");
const Gc = @import("gc.zig");

// This error handling is terrible, I think.
pub const Error = error{
    BadArgumentCount,
    WordNotDefined,
    BadArgumentType,
    OutOfMemory,
    InvalidBase,
    InvalidCharacter,
    WriteFailed,
};

pub const Builtin = *const fn (
    allocator: std.mem.Allocator,
    env: *Environment,
    arguments: []Gc.Handle,
) Error!Gc.Handle;

// Should return a list?
// Namespacing...
pub fn builtins(
    allocator: std.mem.Allocator,
    env: *Environment,
    _: []Gc.Handle,
) Error!Gc.Handle {
    const decls = @typeInfo(@This()).@"struct".decls;

    inline for (decls) |decl| {
        if (@typeInfo(@TypeOf(@field(@This(), decl.name))) == .@"fn")
            try env.writer.print("{s}\n", .{decl.name});
    }

    return env.gc.alloc(allocator, .nothing, .protected);
}

// TODO: improve this.
pub fn help(
    allocator: std.mem.Allocator,
    env: *Environment,
    arguments: []Gc.Handle,
) Error!Gc.Handle {
    if (arguments.len == 0) {
        try env.writer.print(
            \\Type `help syntax` for an explanation of the language syntax.
            \\Type `help words` for a list of currently defined words.
            \\
        , .{});
        return env.gc.alloc(allocator, .nothing, .protected);
    }

    const value = env.gc.get(arguments[0]).*;
    if (value != .string) return error.BadArgumentType;

    const topic = value.string;

    // There should be a smarter comptime hashmap way, I think.
    // Dunno :3
    if (std.mem.eql(u8, topic, "syntax")) {
        try env.writer.print("{s}", .{@embedFile("help.md")});
    } else if (std.mem.eql(u8, topic, "words")) {
        var maybe_context: ?Gc.Handle = env.context;
        while (maybe_context) |context_handle| {
            const context = env.gc.get(context_handle).context;

            var iterator = context.words.keyIterator();

            while (iterator.next()) |word| {
                try env.writer.print("word: {s}\n", .{word.*});
            }

            maybe_context = context.parent;
        }
    }

    return env.gc.alloc(allocator, .nothing, .protected);
}

pub fn @"same strings?"(
    allocator: std.mem.Allocator,
    env: *Environment,
    arguments: []Gc.Handle,
) Error!Gc.Handle {
    var maybe_scrutinee: ?[]const u8 = null;
    for (arguments) |argument|
        switch (env.gc.get(argument).*) {
            .string => |string| {
                if (maybe_scrutinee) |scrutinee| {
                    // Using nothing for falsity is cringe?
                    // Using string false is also cringe.
                    if (!std.mem.eql(
                        u8,
                        scrutinee,
                        string,
                    )) {
                        return env.gc.alloc(
                            allocator,
                            .{
                                .string = try allocator.dupe(u8, "false"),
                            },
                            .protected,
                        );
                    }
                } else maybe_scrutinee = string;
            },
            else => return error.BadArgumentType,
        };

    return env.gc.alloc(
        allocator,
        .{ .string = try allocator.dupe(u8, "true") },
        .protected,
    );
}

pub fn get(
    _: std.mem.Allocator,
    env: *Environment,
    arguments: []Gc.Handle,
) Error!Gc.Handle {
    if (arguments.len != 1) return error.BadArgumentCount;
    switch (env.gc.get(arguments[0]).*) {
        .string => |word| if (env.lookup(word)) |value|
            return env.gc.protected(value.*)
        else
            return error.WordNotDefined,
        else => return error.BadArgumentType,
    }
}

// Error handling is terrible!

pub fn set(
    allocator: std.mem.Allocator,
    env: *Environment,
    arguments: []Gc.Handle,
) Error!Gc.Handle {
    if (arguments.len != 2) return error.BadArgumentCount;

    switch (env.gc.get(arguments[0]).*) {
        .string => |word| if (env.lookup(word)) |slot| {
            slot.* = arguments[1];
        } else return error.WordNotDefined,
        else => return error.BadArgumentType,
    }

    return env.gc.alloc(allocator, .nothing, .protected);
}

pub fn @"<="(
    _: std.mem.Allocator,
    env: *Environment,
    arguments: []Gc.Handle,
) Error!Gc.Handle {
    if (arguments.len != 1) return error.BadArgumentCount;
    return env.gc.protected(arguments[0]);
}

pub fn let(
    allocator: std.mem.Allocator,
    env: *Environment,
    arguments: []Gc.Handle,
) Error!Gc.Handle {
    if (arguments.len != 2) return error.BadArgumentCount;
    const word = blk: switch (env.gc.get(arguments[0]).*) {
        .string => |string| {
            break :blk try allocator.dupe(u8, string);
        },
        else => return error.BadArgumentType,
    };
    // Value doesn't need protection, I think.
    // We put it into the stack immediately.
    const value = arguments[1];
    // Does this compile without &?
    const context = &env.gc.get(env.context).context;
    try context.words.put(allocator, word, value);
    return env.gc.alloc(allocator, .nothing, .protected);
}

// Concat? UwU.
// Pass gc individually from env?
// Env is not needed everywhere.
// Gc is needed more often, kinda?
// UwU.
// errdefer is not used in other places btw.
pub fn cat(
    allocator: std.mem.Allocator,
    env: *Environment,
    arguments: []Gc.Handle,
) Error!Gc.Handle {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    for (arguments) |argument| {
        const value = env.gc.get(argument);
        switch (value.*) {
            .string => |string| {
                for (string) |char| {
                    // Optimize?
                    try result.append(allocator, char);
                }
            },
            else => return error.BadArgumentType,
        }
    }

    const string = try result.toOwnedSlice(allocator);
    errdefer allocator.free(string);
    return env.gc.alloc(allocator, .{ .string = string }, .protected);
}

pub fn echo(
    allocator: std.mem.Allocator,
    env: *Environment,
    arguments: []Gc.Handle,
) Error!Gc.Handle {
    for (arguments, 0..) |argument, i| {
        const value = env.gc.get(argument);
        switch (value.*) {
            .string => |string| {
                try env.writer.print(
                    "{s}{s}",
                    .{
                        if (i == 0) "" else " ",
                        string,
                    },
                );
            },
            else => return error.BadArgumentType,
        }
    }

    try env.writer.print("\n", .{});
    try env.writer.flush();

    return env.gc.alloc(allocator, .nothing, .protected);
}

pub fn add(
    allocator: std.mem.Allocator,
    env: *Environment,
    arguments: []Gc.Handle,
) Error!Gc.Handle {
    const big = std.math.big.int.Managed;

    var number = try big.initSet(allocator, 0);

    defer number.deinit();

    for (arguments) |argument| {
        switch (env.gc.get(argument).*) {
            .string => |string| {
                var other = try big.init(allocator);
                defer other.deinit();
                try other.setString(10, string);
                try number.add(&number, &other);
            },
            else => return error.BadArgumentType,
        }
    }

    return env.gc.alloc(
        allocator,
        .{ .string = try number.toString(allocator, 10, .lower) },
        .protected,
    );
}

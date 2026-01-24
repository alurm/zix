// # Wanted builtins
//
// - set
// - cat, ..
// - del?

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
};

pub const Builtin = *const fn (
    allocator: std.mem.Allocator,
    env: *Environment,
    arguments: []Gc.Handle,
) Error!Gc.Handle;

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

pub fn @"=>"(
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

// pub fn set(
//     allocator: std.mem.Allocator,
//     env: *Environment,
//     arguments: []Gc.Handle,
// ) Error!Gc.Handle {}

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

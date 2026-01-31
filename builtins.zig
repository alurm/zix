// # Wanted builtins/idioms
//
// - __name__ == '__main__'?
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
// - call (requires some form of a list)
// - macros?
// - !
// - json?
// - wasm
// - js
// - c
// - pipes
// - \
// - ;
// - hashmaps, objects, namespaces, returns, imports, aliases
//
// $(unix pipe) process ls
// $(unix process complete) \
//   args $(list a b c)
//   stdin $(some file)
//   stdout $(none)
// ;
// use unix $(math map process p pipe ())
// unix pipe \
//  $(unix process ls)
//  $(unix progress grep)
// ;

const std = @import("std");

const Environment = @import("environment.zig");
const Gc = @import("gc.zig");
const Parser = @import("parser.zig");
const Value = @import("value.zig").Value;
const values = @import("value.zig");

// This error handling is terrible, I think.
pub const Error = error{
    BadArgument,
    BadArgumentCount,
    WordNotDefined,
    BadArgumentType,
    OutOfMemory,
    InvalidBase,
    InvalidCharacter,
    WriteFailed,
    ValueOfCommandIsString,
    ValueOfCommandIsNothing,
    CommandNotFound,
    ExpressionTypeNotImplemented,
    EvaluationOfClosuresIsNotImplemented,
};

pub const Builtin = *const fn (
    allocator: std.mem.Allocator,
    env: *Environment,
    arguments: []Gc.Handle,
) Error!Gc.Handle;

// Dedup this with evaluate_statement.
// Can arguments get mutated during execution of condition?
// Is this UB?
pub fn loop(
    allocator: std.mem.Allocator,
    env: *Environment,
    arguments: []Gc.Handle,
) Error!Gc.Handle {
    if (arguments.len != 1)
        return error.BadArgumentCount;
    // const condition_handle, const body_handle = arguments[0..2].*;
    // var value: Value = undefined;
    // value = env.gc.get(condition_handle).*;
    var value = env.gc.get(arguments[0]).*;
    // Hack, not correct.
    if (value != .closure) return error.BadArgumentType;
    const condition = value.closure;
    // value = env.gc.get(body_handle).*;
    // if (value != .closure) return error.BadArgumentType;
    // const body = value.closure;

    while (true) {
        const handle = try evaluate_closure(allocator, env, condition);
        defer env.gc.unprotect(handle);
        value = env.gc.get(handle).*;
        switch (value) {
            // .nothing => return env.gc.alloc(allocator, .nothing, .protected),
            // Broooo I don't know.
            .string => |string| {
                if (std.mem.eql(u8, string, "false")) break;
            },
            else => {},
        }
    }

    return env.gc.alloc(allocator, .nothing, .protected);
}

// Bruh...
// Move.
fn evaluate_closure(
    allocator: std.mem.Allocator,
    env: *Environment,
    closure: values.Closure,
) !Gc.Handle {
    const old_context = env.context;
    defer env.context = old_context;
    env.context = closure.context;
    return Environment.evaluate_block(env, allocator, closure.block);
}

// Should return a list?
// Namespacing...
pub fn builtins(
    allocator: std.mem.Allocator,
    env: *Environment,
    _: []Gc.Handle,
) Error!Gc.Handle {
    const decls = @typeInfo(@This()).@"struct".decls;

    inline for (decls) |decl| {
        if (@typeInfo(@TypeOf(@field(@This(), decl.name))) == .@"fn") {
            try Parser.pretty_print_string(env.writer, decl.name);
            try env.writer.print("\n", .{});
        }
    }

    return env.gc.alloc(allocator, .nothing, .protected);
}

// pub fn @"!"(
//     allocator: std.mem.Allocator,
//     env: *Environment,
//     arguments: []Gc.Handle,
// ) Error!Gc.Handle {
//     std.process.run;
// }

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
                // Use {f} please.
                try Parser.pretty_print_string(env.writer, word.*);
                try env.writer.print("\n", .{});
                try env.writer.flush();
            }

            maybe_context = context.parent;
        }
    }

    return env.gc.alloc(allocator, .nothing, .protected);
}

pub fn not(
    allocator: std.mem.Allocator,
    env: *Environment,
    arguments: []Gc.Handle,
) Error!Gc.Handle {
    if (arguments.len != 1) return error.BadArgumentCount;

    const value = env.gc.get(arguments[0]).*;

    if (value != .string) return error.BadArgumentType;

    const string = value.string;

    if (std.mem.eql(u8, string, "true"))
        return env.gc.alloc(
            allocator,
            .{ .string = try allocator.dupe(u8, "false") },
            .protected,
        );

    if (std.mem.eql(u8, string, "false"))
        return env.gc.alloc(
            allocator,
            .{ .string = try allocator.dupe(u8, "true") },
            .protected,
        );

    return error.BadArgument;
}

pub fn @"same?"(
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

// Bruh!!!
// Dedup with let and others!
pub fn global(
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

    const value = arguments[1];

    // &&&&????
    var context = &env.gc.get(env.context).context;

    while (context.parent) |parent| {
        context = &env.gc.get(parent).context;
    }

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

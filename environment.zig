// TODO: fix error reporting.

const std = @import("std");

const builtins = @import("builtins.zig");
const Gc = @import("gc.zig");
const Parser = @import("parser.zig");

const Self = @This();
gc: Gc,

// Get rid of usizes?

// We protect and unprotect everything manually.
// Gc is not aware of context.
// Is this a good idea?
context: *Context,

pub const Context = struct {
    ref_count: usize,
    context: ?*Context,
    words: std.StringHashMapUnmanaged(Gc.Handle) = .empty,

    fn init(context: *Context) @This() {
        context.ref_count += 1;
        return .{
            .ref_count = 1,
            .context = context,
        };
    }

    // Is this badly named?
    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
        gc: *Gc,
    ) void {
        var context: ?*@This() = self;

        while (context) |c| {
            c.ref_count -= 1;

            if (c.ref_count != 0) {
                break;
            }

            var iterator = self.words.iterator();

            while (iterator.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                gc.unprotect(entry.value_ptr.*);
            }

            self.words.deinit(allocator);

            context = c.context;

            // Is this supposed to be done?
            // I'm confused.
            allocator.destroy(c);
        }
    }
};

pub fn lookup(self: @This(), string: []const u8) ?Gc.Handle {
    var context: ?*const Context = self.context;
    while (context) |c| {
        if (c.words.get(string)) |handle| return handle;
        context = c.context;
    }
    return null;
}

const Error = error{
    OutOfMemory,
    ValueOfCommandIsString,
    ValueOfCommandIsNothing,
    CommandNotFound,
    // This should be removed.
    ExpressionTypeNotImplemented,
    EvaluationOfClosuresIsNotImplemented,
} || builtins.Error;

pub fn evaluate_expression(self: *Self, allocator: std.mem.Allocator, expression: *Parser.Expression) Error!Gc.Handle {
    return switch (expression.*) {
        .string => |string| self.gc.alloc(
            allocator,
            .{ .string = try allocator.dupe(u8, string) },
            .protected,
        ),
        .block => |block| {
            const new_context = try allocator.create(Context);
            const old_context = self.context;

            new_context.* = .init(old_context);
            self.context = new_context;

            defer {
                self.context.deinit(allocator, &self.gc);
                self.context = old_context;
            }

            var result = try self.gc.alloc(allocator, .nothing, .protected);
            for (block.statements) |statement| {
                self.gc.unprotect(result);
                result = try self.evaluate_statement(allocator, statement);
            }
            return result;
        },
        .closure => |block| {
            self.context.ref_count += 1;
            block.ref_count += 1;
            const closure = try self.gc.alloc(
                allocator,
                .{
                    .closure = .{
                        .block = block,
                        .context = self.context,
                    },
                },
                .protected,
            );
            // I don't know if this is enough.
            return closure;
        },
    };
}

pub fn init(allocator: std.mem.Allocator) !@This() {
    const context = try allocator.create(Context);
    context.* = .{ .context = null, .ref_count = 1 };
    return .{
        .gc = .init(.disabled),
        .context = context,
    };
}

// This is a mess.
pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    self.context.deinit(allocator, &self.gc);
    self.gc.deinit(allocator);
}

pub fn evaluate_statement(
    self: *Self,
    allocator: std.mem.Allocator,
    statement: *Parser.Statement,
) !Gc.Handle {
    // Not sure about rooting here.
    const command = blk: {
        const value = try self.evaluate_expression(allocator, statement.command);
        break :blk switch (self.gc.get(value).*) {
            .string => |string| if (self.lookup(string)) |val| blk2: {
                self.gc.unprotect(value);
                self.gc.protect(val);
                break :blk2 val;
            } else return error.CommandNotFound,
            else => value,
        };
    };
    defer self.gc.unprotect(command);

    const arguments = try allocator.alloc(Gc.Handle, statement.arguments.len);
    defer allocator.free(arguments);
    defer for (arguments) |argument| self.gc.unprotect(argument);

    for (statement.arguments, 0..) |argument, i|
        arguments[i] = try self.evaluate_expression(allocator, argument);

    switch (self.gc.get(command).*) {
        .string => return error.ValueOfCommandIsString,
        .closure => return error.EvaluationOfClosuresIsNotImplemented,
        .builtin => |builtin| {
            // return error.BuiltinsAreNotImplemented,
            const result = try builtin(allocator, self, arguments);
            // Is this correct?
            // We protect in builtins.
            // self.gc.protect(result);
            return result;
        },
        // .builtin => |builtin| return if (std.mem.eql(u8, builtin, "get")) {
        //     if (self.words.get(arguments[0].string)) |value| return value;
        //     return error.WordNotDefined;
        // } else if (eq(builtin, "let")) {
        //     // FIXME: use stack.
        //     // This is broken btw. Implement a GC.
        //     // const name = try allocator.dupe(u8, arguments[0].string);
        //     // const value = arguments[1];
        //     // try self.words.put(allocator, name, value);
        //     return .nothing;
        // } else if (eq(builtin, "=>")) {
        //     // FIXME: rename this?
        //     // FIXME: this is broken.
        //     // return arguments[0];
        //     return .nothing;
        // } else if (eq(builtin, "set")) {
        //     // FIXME: use stack.
        //     // This is broken btw. Implement a GC.
        //     // const name = try allocator.dupe(u8, arguments[0].string);
        //     // const value = arguments[1];
        //     // try self.words.put(allocator, name, value);
        //     return .nothing;
        // } else if (eq(builtin, "help")) {
        //     // FIXME: consider not using debug.print.

        //     if (arguments.len == 0) {
        //         std.debug.print(
        //             \\- `help syntax`: explains the syntax of the language.
        //             \\- `help words`: provides a list of currently defined words.
        //             \\
        //         , .{});
        //         return .nothing;
        //     }

        //     const argument = arguments[0].string;

        //     if (eq(argument, "syntax")) {
        //         // TODO: update the docs once mutliline statements are supported.
        //         // TODO: improve this. This is too long.
        //         const help = @embedFile("help.md");
        //         std.debug.print("{s}", .{help});
        //     } else if (eq(argument, "words")) {
        //         var iterator = self.words.keyIterator();
        //         while (iterator.next()) |word|
        //             std.debug.print("- {s}\n", .{word.*});
        //     } else {
        //         std.debug.print("Type `help` for a list of help topics.\n", .{});
        //     }

        //     return .nothing;
        // } else return error.BuiltinNotDefined,
        .nothing => return error.ValueOfCommandIsNothing,
    }
}

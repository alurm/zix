// TODO: fix error reporting.

const Parser = @import("parser.zig");

const Self = @This();
const std = @import("std");

words: std.StringHashMapUnmanaged(Value) = .empty,

pub const Value = union(enum) {
    string: []const u8,
    // This is ugly.
    builtin: []const u8,
    // Have this for now.
    nothing: void,

    pub fn deinit(value: @This(), allocator: std.mem.Allocator) void {
        switch (value) {
            .string => |string| allocator.free(string),
            // OwO.
            .builtin => {},
            .nothing => {},
        }
    }
};

pub fn evaluate_expression(self: *Self, expression: Parser.Expression) !Value {
    _ = self;

    return switch (expression) {
        .string => |string| .{ .string = string },
        else => error.ExpressionTypeNotImplemented,
    };
}

pub fn default(allocator: std.mem.Allocator) !@This() {
    var words: std.StringHashMapUnmanaged(Value) = .empty;

    // FIXME: this is annoying how this must be in sync.
    for ([_][]const u8{ "get", "let", "set", "help", "=>" }) |builtin|
        try words.put(allocator, builtin, .{ .builtin = builtin });
    return .{
        .words = words,
    };
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn evaluate_statement(
    self: *Self,
    allocator: std.mem.Allocator,
    statement: Parser.Statement,
) !Value {
    const command = blk: {
        const value = try self.evaluate_expression(statement.command);
        break :blk switch (value) {
            .string => |string| if (self.words.get(string)) |val| val else return error.CommandNotFound,
            else => value,
        };
    };

    const arguments = try allocator.alloc(Value, statement.arguments.len);
    defer allocator.free(arguments);

    for (statement.arguments, 0..) |argument, i|
        arguments[i] = try self.evaluate_expression(argument);

    switch (command) {
        .string => return error.ValueOfCommandIsString,
        .builtin => |builtin| return if (std.mem.eql(u8, builtin, "get")) {
            if (self.words.get(arguments[0].string)) |value| return value;
            return error.WordNotDefined;
        } else if (eq(builtin, "let")) {
            // FIXME: use stack.
            // This is broken btw. Implement a GC.
            // const name = try allocator.dupe(u8, arguments[0].string);
            // const value = arguments[1];
            // try self.words.put(allocator, name, value);
            return .nothing;
        } else if (eq(builtin, "=>")) {
            // FIXME: rename this?
            // FIXME: this is broken.
            // return arguments[0];
            return .nothing;
        } else if (eq(builtin, "set")) {
            // FIXME: use stack.
            // This is broken btw. Implement a GC.
            // const name = try allocator.dupe(u8, arguments[0].string);
            // const value = arguments[1];
            // try self.words.put(allocator, name, value);
            return .nothing;
        } else if (eq(builtin, "help")) {
            // FIXME: consider not using debug.print.

            if (arguments.len == 0) {
                std.debug.print(
                    \\- `help syntax`: explains the syntax of the language.
                    \\- `help words`: provides a list of currently defined words.
                    \\
                , .{});
                return .nothing;
            }

            const argument = arguments[0].string;

            if (eq(argument, "syntax")) {
                // TODO: update the docs once mutliline statements are supported.
                // TODO: improve this. This is too long.
                const help = @embedFile("help.md");
                std.debug.print("{s}", .{help});
            } else if (eq(argument, "words")) {
                var iterator = self.words.keyIterator();
                while (iterator.next()) |word|
                    std.debug.print("- {s}\n", .{word.*});
            } else {
                std.debug.print("Type `help` for a list of help topics.\n", .{});
            }

            return .nothing;
        } else return error.BuiltinNotDefined,
        .nothing => return error.ValueOfCommandIsNothing,
    }
}

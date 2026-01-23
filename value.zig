const std = @import("std");

const builtins = @import("builtins.zig");

const Parser = @import("parser.zig");

const Environment = @import("environment.zig");

const Gc = @import("gc.zig");

pub const Closure = struct {
    block: *Parser.Block,
    context: *Environment.Context,
};

pub const Value = union(enum) {
    string: []const u8,
    builtin: builtins.Builtin,
    // Have this for now.
    nothing: void,

    closure: Closure,

    pub fn deinit(value: *@This(), allocator: std.mem.Allocator, gc: *Gc) void {
        switch (value.*) {
            .string => |string| {
                allocator.free(string);
            },
            // OwO.
            .builtin => {},
            .nothing => {},
            // Watafak why
            // let closure ()
            // )
            // leak...
            .closure => |closure| {
                closure.block.deinit(allocator);
                // allocator.destroy(closure.block);
                // This can go wrong?
                closure.context.deinit(allocator, gc);
                // allocator.destroy(closure.context);
            },
        }
    }

    // TODO.
    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        return switch (self) {
            // Should pretty print.
            .string => |string| writer.print("{s}", .{string}),
            // Should be removed.
            .nothing => writer.print("<nothing>", .{}),
            // Bad.
            .builtin => writer.print("<builtin>", .{}),
            // Bad.
            .closure => writer.print("<closure>", .{}),
        };
    }
};

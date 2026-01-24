const std = @import("std");

const builtins = @import("builtins.zig");

const Parser = @import("parser.zig");

const Environment = @import("environment.zig");

const Gc = @import("gc.zig");

pub const Closure = struct {
    block: *Parser.Block,
    context: Gc.Handle,
};

pub const Value = union(enum) {
    string: []const u8,
    builtin: builtins.Builtin,
    // Have this for now.
    nothing: void,

    closure: Closure,

    context: Environment.Context,

    pub fn deinit(value: *@This(), allocator: std.mem.Allocator) void {
        // std.debug.print("value.deinit\n", .{});
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
                // allocator.destroy(closure.context);
            },
            .context => |*context| {
                // Must stop protecting context values.

                var iterator = context.words.keyIterator();

                while (iterator.next()) |word| {
                    allocator.free(word.*);
                }

                context.words.deinit(allocator);
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
            .context => unreachable,
        };
    }
};

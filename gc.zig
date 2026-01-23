// Each object may have a link to the next object in the chain.
// TODO: name files appropriately.
// Files which name a type should be capitalized.
// Returning ! on bugs seems stupid?
// TODO: unsure if .rehash or .shrink_to_fit would be needed or helpful (like in Rust).
// Maybe a new map can be made after a collection.
// TODO: we are not passing allocator everywhere here.

const std = @import("std");

const Environment = @import("environment.zig");
const Value = @import("value.zig").Value;

map: std.AutoHashMapUnmanaged(Handle, Entry),
counter: usize,
capacity: usize,
mode: Mode,

const Entry = struct {
    value: Value,
    // Incremented when protected from collection.
    protections: usize,
    reachable: bool,
};

pub const Handle = enum(usize) { _ };

pub const Mode = enum {
    // Collect when the amount of objects doubles.
    default,
    // Collect on each allocation.
    aggressive,
    // Don't collect.
    disabled,
};

pub fn init(mode: Mode) @This() {
    return .{
        .counter = 0,
        .capacity = 0,
        .map = .empty,
        .mode = mode,
    };
}

// Not sure if this is correct.
fn trace(allocator: std.mem.Allocator, value: Value) ![]const Handle {
    var traces: std.ArrayList(Handle) = .empty;

    switch (value) {
        .nothing => {},
        .builtin => {},
        .string => {},
        else => unreachable,
    }

    return traces.toOwnedSlice(allocator);
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    var iterator = self.map.valueIterator();
    while (iterator.next()) |value| {
        // Sus.
        if (value.protections == 0) value.*.value.deinit(allocator, self);
    }
    self.map.deinit(allocator);
}

fn gc(self: *@This(), allocator: std.mem.Allocator) !void {
    std.debug.print("gc\n", .{});

    // Add all protected objects to the queue and mark them as reachable.
    var queue = blk: {
        var queue: std.ArrayList(Handle) = .empty;
        var iterator = self.map.iterator();
        while (iterator.next()) |entry|
            if (entry.value_ptr.protections > 0) {
                entry.value_ptr.reachable = true;
                try queue.append(allocator, entry.key_ptr.*);
            };
        break :blk queue;
    };

    // Mark all transitively reachable objects.
    while (queue.pop()) |handle| {
        const value = self.map.get(handle).?;
        const traces = try trace(allocator, value.value);
        defer allocator.free(traces);
        for (traces) |t| {
            self.map.getPtr(t).?.reachable = true;
            try queue.append(allocator, t);
        }
    }

    // Copy only reachable objects // and create a list of dead.
    // Maybe a new map is not needed, this is not clear to me.
    self.map = blk: {
        var map: std.AutoHashMapUnmanaged(Handle, Entry) = .empty;
        var iterator = self.map.iterator();
        while (iterator.next()) |entry| if (entry.value_ptr.reachable) {
            var value = entry.value_ptr.*;
            value.reachable = false;
            try map.put(allocator, entry.key_ptr.*, value);
        } else {
            // Shouldn't values be deinited as well?
            // OwO.
            // How to deinit keys in other hashmaps...
            // I don't know.
            // Self? This can go wrong?
            entry.value_ptr.*.value.deinit(allocator, self);
        };
        self.map.deinit(allocator);
        break :blk map;
    };
    self.capacity = self.map.count() * 2 + 1;
}

pub fn alloc(
    self: *@This(),
    allocator: std.mem.Allocator,
    value: Value,
    protection: enum { protected, unprotected },
) !Handle {
    switch (self.mode) {
        .disabled => {},
        .default => if (self.map.count() > self.capacity)
            try self.gc(allocator),
        .aggressive => try self.gc(allocator),
    }
    self.counter += 1;
    const handle: Handle = @enumFromInt(self.counter);
    try self.map.put(allocator, handle, .{
        .value = value,
        .protections = switch (protection) {
            .protected => 1,
            .unprotected => 0,
        },
        .reachable = false,
    });
    return handle;
}

pub fn protect(self: *@This(), value: Handle) void {
    self.map.getPtr(value).?.protections += 1;
}

// A convenience method.
pub fn protected(self: *@This(), value: Handle) Handle {
    self.protect(value);
    return value;
}

pub fn unprotect(self: *@This(), value: Handle) void {
    self.map.getPtr(value).?.protections -= 1;
}

// Shouldn't this return by value?
pub fn get(self: *@This(), value: Handle) *Value {
    const ptr = self.map.getPtr(value).?;
    std.debug.assert(ptr.protections != 0);
    return &ptr.value;
}

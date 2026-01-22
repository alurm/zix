// Each object may have a link to the next object in the chain.
// TODO: name files appropriately.
// Files which name a type should be capitalized.
// Returning ! on bugs seems stupid?
// TODO: unsure if .rehash or .shrink_to_fit would be needed or helpful (like in Rust).
// Maybe a new map can be made after a collection.
// TODO: we are not passing allocator everywhere here.

const std = @import("std");

const Environment = @import("environment.zig");

// TODO: make this unmanaged?
map: std.AutoHashMap(Handle, Entry),
counter: usize,
capacity: usize,

const Entry = struct {
    value: Environment.Value,
    // Incremented when protected from collection.
    protections: usize,
    reachable: bool,
};

const Handle = enum(usize) { _ };

pub fn init(allocator: std.mem.Allocator) @This() {
    return .{
        .counter = 0,
        .capacity = 0,
        .map = .init(allocator),
    };
}

fn trace(allocator: std.mem.Allocator, value: Environment.Value) ![]const Handle {
    var traces: std.ArrayList(Handle) = .empty;

    switch (value) {
        .nothing => {},
        .builtin => {},
        .string => {},
    }

    return traces.toOwnedSlice(allocator);
}

pub fn deinit(self: *@This()) void {
    self.map.deinit();
}

fn gc(self: *@This()) !void {
    std.debug.print("gc\n", .{});

    const allocator = self.map.allocator;

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
        var map: std.AutoHashMap(Handle, Entry) = .init(allocator);
        var iterator = self.map.iterator();
        while (iterator.next()) |entry| if (entry.value_ptr.reachable) {
            var value = entry.value_ptr.*;
            value.reachable = false;
            try map.put(entry.key_ptr.*, value);
        } else {
            // Shouldn't values be deinited as well?
            // OwO.
            // How to deinit keys in other hashmaps...
            // I don't know.
            entry.value_ptr.*.value.deinit(allocator);
        };
        self.map.deinit();
        break :blk map;
    };
    self.capacity = self.map.count() * 2 + 1;
}

pub fn alloc(self: *@This(), value: Environment.Value, protected: bool) !Handle {
    // TODO: can have different modes to collect always or never.
    if (self.map.count() > self.capacity) try self.gc();
    self.counter += 1;
    const handle: Handle = @enumFromInt(self.counter);
    try self.map.put(handle, .{
        .value = value,
        .protections = if (protected) 1 else 0,
        .reachable = false,
    });
    return handle;
}

pub fn protect(self: *@This(), value: Handle) void {
    self.map.get(value).?.protections += 1;
}

pub fn unprotect(self: *@This(), value: Handle) void {
    self.map.get(value).?.protections -= 1;
}

pub fn get(self: *@This(), value: Handle) *Environment.Value {
    return &self.map.getPtr(value).?.value;
}

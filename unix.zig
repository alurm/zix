const builtins = @import("builtins.zig");
const Environment = @import("environment.zig");
const Gc = @import("gc.zig");
const std = @import("std");

// ! ls
// fn @"!"(
//     allocator: std.mem.Allocator,
//     env: *Environment,
//     arguments: []Gc.Handle,
// ) builtins.Error {
//     // std.process.
// }

// I'm not sure if I understand how the module system works in terms of laziness.
// Maybe something like comptime { _ = ... } can be useful for some files.
// Maybe not.

pub const Tokenizer = @import("tokenizer.zig");
pub const parser = @import("parser.zig");

// TODO: understand what in the world is this.
// https://ziggit.dev/t/how-do-i-get-zig-build-to-run-all-the-tests/4434
// Makes tests from other files run on zig test main.zig.
// Perhaps can be removed when the Zig build system is used more extensively.
// I don't know.
// Perhaps it would be better to reference each file manually, if there's a way to do this.
test {
    @import("std").testing.refAllDecls(@This());
}

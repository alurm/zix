// NOTE: parser is probably fucked? IDK.
// Does ReleaseSafe used?
// Does ReleaseSafe make sense for Wasm?

const std = @import("std");

const allocator = std.heap.wasm_allocator;

comptime {
    _ = Js;
}

const Js = struct {
    export fn allocate(length: usize) *[]u8 {
        const slice = allocator.alloc(u8, length) catch unreachable;
        const slice_ptr = allocator.create([]u8) catch unreachable;
        slice_ptr.* = slice;
        return slice_ptr;
    }

    export fn ptr(input: *[]u8) [*]u8 {
        return input.ptr;
    }

    export fn len(input: *[]u8) usize {
        return input.len;
    }

    export fn free(input: *[]u8) void {
        allocator.free(input.*);
        allocator.destroy(input);
    }

    export fn interpret(input: *[]u8) *[]u8 {
        defer free(input);
        {
            const v1 = allocator.dupe(u8, "Hey!") catch unreachable;
            const v2 = allocator.create([]u8) catch unreachable;
            v2.* = v1;
            return v2;
        }
    }
};

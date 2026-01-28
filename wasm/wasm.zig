// extern fn print(i32) void;

const std = @import("std");

export fn zoo() usize {
    return @sizeOf(*u8);
}

export fn t() void {
    unreachable;
}

export fn bar() *[]const u8 {
    const hello = allocator.dupe(u8, "hello") catch undefined;
    const ptr = allocator.create([]const u8) catch undefined;
    ptr.* = hello;
    return ptr;
}

export fn bee() *const []const u8 {
    return &"foo";
}

export fn foo() [*]const u8 {
    // export fn foo() usize {
    // DebugAllocator(.{});
    const slice = allocator.alloc(u8, 3) catch undefined;
    slice[0] = 'a';
    slice[1] = 'b';
    slice[2] = 'c';
    return slice.ptr;
    // return "foo";
}

// export fn add(a: i32, b: i32) void {
//     print(a + b);
// }

// export fn dup(a: i32) void {
//     print(a + a);
// }

fn transform_impl(input: []const u8) []u8 {
    const output = allocator.alloc(
        u8,
        input.len * 2,
    ) catch unreachable;
    for (0..input.len / 2) |left| {
        const right = input.len - 1 - left;
        output[left] = input[right];
        output[right] = input[left];
    }
    if (input.len % 2 == 1) output[input.len / 2] = input[input.len / 2];
    for (0..input.len) |i| {
        output[input.len + i] = input[i];
    }
    return output;
}

export fn free(slice_ptr: *[]u8) void {
    allocator.free(slice_ptr.*);
    allocator.destroy(slice_ptr);
}

// I'm not sure if it's ok to pass pointers like that across FFI.
// Should be ok? IDK.

export fn allocate(n: usize) *[]u8 {
    const slice = allocator.alloc(u8, n) catch unreachable;
    const slice_ptr = allocator.create([]u8) catch unreachable;
    slice_ptr.* = slice;
    return slice_ptr;
}

export fn address(it: *[]u8) [*]u8 {
    return it.ptr;
}

export fn length(it: *[]u8) usize {
    return it.len;
}

const allocator = std.heap.wasm_allocator;

export fn transform(input_slice_ptr: *[]const u8) *[]u8 {
    const slice = transform_impl(input_slice_ptr.*);
    const slice_ptr = allocator.create([]u8) catch unreachable;
    slice_ptr.* = slice;
    return slice_ptr;
}

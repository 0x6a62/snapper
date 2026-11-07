# Snapper 

Snapshot testing library in Zig

# Components

* Modules
  * snapper
* Example usage
  * main

# Development

Zig target version: 0.17.1

```
# Build
zig build

# Run example
zig build run

# Test
zig build test --summary all
```

# Usage

## Install
```
zig fetch --save git+https://github.com/0x6a62/snapper.git
```

## Add to your `build.zig`
```
const snapper = b.dependency("snapper", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("snapper", snapper.module("snapper"));
```

## Using in code
```
// Import library
const snapper = @import("snapper");

/// Results saved in ./snapshots directory
test "foo" {
    const data = [5]f32{ 1.23, 2.34, 3.45, 4.56, 5.67 };
    try compare(std.testing.io, std.testing.allocator, @src(), data);
}

// Direct comparison, no snapshot file saved
test "bar" {
    const expected: i32 = 1001;
    const actual: i32 = 1001;
    try expect(std.testing.allocator, @src(), expected, actual);
}
```

# References


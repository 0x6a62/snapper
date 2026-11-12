// Snapper module
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Io = std.Io;
const print = std.debug.print;
const allocPrint = std.fmt.allocPrint;

const SNAPSHOT_ROOT = "./.snapshots";

/// Stringify value by appending its stringified value(s) to the results array
fn stringify_inner(
    aa: Allocator,
    value: anytype,
    indent: usize,
    results: *ArrayList([]u8),
) !void {
    const ti = @typeInfo(@TypeOf(value));

    // Indents for child objects
    const indent_s = try aa.alloc(u8, indent * 2);
    @memset(indent_s, ' ');
    const indent2_s = try aa.alloc(u8, (indent + 1) * 2);
    @memset(indent2_s, ' ');

    /////////////////////////////
    // header for complex objects
    switch (ti) {
        .array => {
            try results.append(aa, try allocPrint(aa, "{s}[", .{indent_s}));
        },
        .@"struct" => {
            const tn = @typeName(@TypeOf(value));
            try results.append(
                aa,
                try allocPrint(aa, "{s}{s}{{", .{
                    indent_s,
                    if (std.mem.indexOf(u8, tn, "__struct_") == 0)
                        tn
                    else
                        ".",
                }),
            );
        },
        else => {},
    }

    ///////////
    // contents
    switch (ti) {
        .bool => {
            try results.append(aa, try allocPrint(aa, "{s}: {any} = {any}", .{
                indent_s,
                @TypeOf(value),
                value,
            }));
        },
        .int,
        .float,
        .comptime_int,
        .comptime_float,
        => {
            try results.append(aa, try allocPrint(aa, "{s}: {any} = {d}", .{
                indent_s,
                @TypeOf(value),
                value,
            }));
        },
        .array => |a| {
            for (0..a.len) |i| {
                try stringify_inner(aa, value[i], indent + 1, results);
            }
        },
        .pointer => |p| {
            switch (p.size) {
                .one,
                .slice,
                => {
                    const is_string = brk: switch (@typeInfo(p.child)) {
                        .array => |a| if (a.child == u8) true else false,
                        .int => |x| {
                            break :brk (x.signedness == .unsigned and x.bits == 8);
                        },
                        else => false,
                    };

                    if (is_string) {
                        // treat as string
                        try results.append(
                            aa,
                            try allocPrint(aa, "{s}: []u8 = {s}", .{
                                indent_s,
                                value,
                            }),
                        );
                    } else {
                        // treat as array (not string)
                        try results.append(aa, try allocPrint(aa, "{s}[", .{
                            indent_s,
                        }));

                        for (0..value.len) |i| {
                            try stringify_inner(aa, value[i], indent + 1, results);
                        }

                        try results.append(aa, try allocPrint(aa, "{s}]", .{
                            indent_s,
                        }));
                    }
                },
                else => {
                    // Unsupport datatype
                    // NOTE: When this pops up, figure out how to address
                    try results.append(
                        aa,
                        try allocPrint(
                            aa,
                            "TODO: : {any} ({any}) = {any}",
                            .{ @TypeOf(value), p.size, value },
                        ),
                    );
                },
            }
        },
        .@"struct" => |x| {
            // Handle is property in the struct
            inline for (0..x.field_names.len) |i| {
                const sub_value = @field(value, x.field_names[i]);
                switch (@typeInfo(@TypeOf(@field(value, x.field_names[i])))) {
                    .bool => {
                        try results.append(
                            aa,
                            try allocPrint(aa, "{s}.{s}: {any} = {any}", .{
                                indent2_s,
                                x.field_names[i],
                                @TypeOf(@field(value, x.field_names[i])),
                                sub_value,
                            }),
                        );
                    },
                    .int,
                    .float,
                    .comptime_int,
                    .comptime_float,
                    => {
                        // simple value, show name and value on same line
                        try results.append(
                            aa,
                            try allocPrint(aa, "{s}.{s}: {any} = {d}", .{
                                indent2_s,
                                x.field_names[i],
                                @TypeOf(@field(value, x.field_names[i])),
                                sub_value,
                            }),
                        );
                    },
                    else => {
                        // more complex value, name and value are on separate lines
                        try results.append(
                            aa,
                            try allocPrint(aa, "{s}.{s}:", .{
                                indent2_s,
                                x.field_names[i],
                            }),
                        );

                        try stringify_inner(aa, sub_value, indent + 2, results);
                    },
                }
            }
        },
        .@"enum" => {
            try results.append(aa, try allocPrint(aa, "{s}: {any} = {s}", .{
                indent_s,
                @TypeOf(value),
                @tagName(value),
            }));
        },
        .enum_literal => {
            try results.append(aa, try allocPrint(aa, "{s}: {any} = {any}", .{
                indent_s,
                @TypeOf(value),
                value,
            }));
        },
        .@"union" => |u| {
            _ = u;
            try results.append(aa, try allocPrint(aa, "{s}: {any} = {s}{any}", .{
                indent_s,
                @TypeOf(value),
                @tagName(value),
                value,
            }));
        },
        .error_set => {
            try results.append(aa, try allocPrint(aa, "{s}: {any} = {any}", .{
                indent_s,
                @TypeOf(value),
                value,
            }));
        },
        .error_union => |eu| {
            try results.append(aa, try allocPrint(aa, "{s}: !{any} = {any}", .{
                indent_s,
                eu.payload,
                value,
            }));
        },
        .optional => {
            try results.append(aa, try allocPrint(aa, "{s}: {any} = {any}", .{
                indent_s,
                @TypeOf(value),
                value,
            }));
        },
        else => {
            // Unsupport datatype
            // NOTE: When this pops up, figure out how to address
            try results.append(aa, try allocPrint(aa, "TODO: : {any} = {any}", .{
                @TypeOf(value),
                value,
            }));
        },
    }

    /////////////////////////////
    // footer for complex objects
    switch (ti) {
        .array => {
            try results.append(
                aa,
                try allocPrint(aa, "{s}]", .{
                    indent_s,
                }),
            );
        },
        .@"struct" => {
            try results.append(
                aa,
                try allocPrint(aa, "{s}}}", .{
                    indent_s,
                }),
            );
        },
        else => {},
    }
}

/// Stringify value
pub fn stringify(aa: Allocator, value: anytype) ![]u8 {
    const indent = 0;

    var results = ArrayList([]u8).empty;
    defer results.deinit(aa);

    try stringify_inner(aa, value, indent, &results);

    return try std.mem.join(aa, "\n", results.items);
}

/// Compare expected versus actual
pub fn expect(allocator: Allocator, src: std.lang.SourceLocation, expected: anytype, actual: anytype) !void {
    _ = src;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const expected_string = try stringify(aa, expected);
    const actual_string = try stringify(aa, actual);

    // std.debug.print("e: {s}\n", .{expected_string});
    // std.debug.print("a: {s}\n", .{actual_string});

    if (!std.mem.eql(u8, expected_string, actual_string)) {
        // std.log.scoped(.expects).warn("expect failed for {s} {d}:{d} ({s}.{s})\n", .{
        //     src.file,   src.line,    src.column,
        //     src.module, src.fn_name,
        // });
        return error.TestExpectedEqual;
    }
}

/// Get project root
/// NOTE: This should be better
fn get_project_root(file_path: []const u8) []const u8 {
    if (std.mem.lastIndexOf(u8, file_path, "/src/")) |idx| {
        return file_path[0..idx];
    }
    if (std.mem.lastIndexOf(u8, file_path, "\\src\\")) |idx| {
        return file_path[0..idx];
    }
    return file_path;
}

/// Build the name of the snapshot file
fn build_snapshot_name(
    aa: Allocator,
    src: std.lang.SourceLocation,
    snapshot_root: []const u8,
) ![]u8 {
    const snapshot_base_name_prelim = try allocPrint(aa, "{s}_{s}_{s}", .{
        src.file,
        src.module,
        src.fn_name,
    });

    const sanitized1 = try aa.alloc(u8, snapshot_base_name_prelim.len);
    _ = std.mem.replace(u8, snapshot_base_name_prelim, ".", "_", sanitized1);

    const sanitized2 = try aa.alloc(u8, snapshot_base_name_prelim.len);
    _ = std.mem.replace(u8, sanitized1, " ", "_", sanitized2);

    const snapshot_base_name = sanitized2;
    const snapshot_name = try allocPrint(aa, "{s}.snap", .{
        snapshot_base_name,
    });

    const full_path = try std.fs.path.join(aa, &[2][]const u8{
        snapshot_root,
        snapshot_name,
    });

    return full_path;
}

/// Determine if the file exists
fn file_exists(io: Io, file_name: []const u8) bool {
    _ = std.Io.Dir.cwd().access(io, file_name, .{}) catch |e| {
        if (e == error.FileNotFound) {
            return false;
        }
    };
    return true;
}

/// Compare snapshots
/// If file exists, compare actual versus file
/// If file doesn't exist, this is a new snapshot, create file with actual contents
pub fn compare(
    io: Io,
    allocator: Allocator,
    src: std.lang.SourceLocation,
    actual: anytype,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const buffer_size = 4096; // should be able to hold a full snaphot line
    const actual_s = try stringify(aa, actual);

    // TODO: find project root and/or allow customization of snapshots path
    std.Io.Dir.createDir(std.Io.Dir.cwd(), io, SNAPSHOT_ROOT, .default_dir) catch |e| {
        if (e == Io.Dir.CreateDirError.PathAlreadyExists) {} else {
            return e;
        }
    };

    const snapshot_name = try build_snapshot_name(aa, src, SNAPSHOT_ROOT);

    // std.log.scoped(.compare).info("{s} exists: {any}", .{
    //     snapshot_name,
    //     file_exists(io, snapshot_name),
    // });

    var dir = try std.Io.Dir.cwd().openDir(io, ".", .{});
    defer dir.close(io);

    if (file_exists(io, snapshot_name)) {
        // Compare actual against existing

        var file = try dir.openFile(io, snapshot_name, .{ .mode = .read_only });
        defer file.close(io);

        var buffer: [buffer_size]u8 = undefined;
        var r = file.reader(io, &buffer);
        var ri = &r.interface;

        const header_len = (try allocPrint(aa, "snapshot: {s}\n", .{snapshot_name})).len;
        r.seekTo(header_len) catch {
            // std.log.scoped(.compare).warn(
            //     "Header seek error: {any} Position: {d}",
            //     .{
            //         e,
            //         header_len,
            //     },
            // );
            return error.TestExpectedEqual;
        };

        // Read through file buffer at a time, doing comparison against actual
        var actual_index: usize = 0;

        // Line by line comparison of file version actual
        while (try ri.takeDelimiter('\n')) |d| {
            const x = d.len;
            if (actual_index > actual_s.len) {
                std.log.scoped(.compare).err(
                    "Size mismatch {d} {d} (end)\n",
                    .{
                        actual_index,
                        actual_s.len,
                    },
                );
                return error.TestExpectedEqual;
            }
            if (actual_index + x > actual_s.len) {
                std.log.scoped(.compare).err(
                    "Size mismatch {d} {d} (end)\n",
                    .{
                        actual_index + x,
                        actual_s.len,
                    },
                );
                return error.TestExpectedEqual;
            }

            // print("e:{s}\n", .{d[0..x]});
            // print("a:{s}\n", .{actual_s[actual_index .. actual_index + x]});

            if (!std.mem.eql(u8, d[0..x], actual_s[actual_index .. actual_index + x])) {
                // failed match
                std.log.scoped(.compare).err(
                    "\nexpected: '{s}'\nactual  : '{s}'",
                    .{
                        d[0..x],
                        actual_s[actual_index .. actual_index + x],
                    },
                );
                return error.TestExpectedEqual;
            }
            // Advance data block + delimiter
            actual_index += x + 1;
        }
    } else {
        // Snapshot doesn't exist, create
        var file = try dir.createFile(io, snapshot_name, .{ .truncate = true });
        defer file.close(io);

        var buffer: [buffer_size]u8 = undefined;
        var w = file.writer(io, &buffer);
        // header
        try w.interface.print("snapshot: {s}\n", .{snapshot_name});
        // data
        try w.interface.writeAll(actual_s);
        try w.flush();
    }
}

////////
// Tests

const Foo = enum {
    Bar,
    Qua,
    Baz,
};

const ShapeTag = enum {
    Circle,
    Rectangle,
    Unknown,
};

const Rectangle = struct { w: i32, h: i32 };

const Shape = union(ShapeTag) {
    Circle: i32,
    Rectangle: Rectangle,
    Unknown: []u8,
};

const User = struct {
    name: []const u8,
    age: i32,
    enabled: bool,
    favorite_shape: Shape,
    ids: []const i8,
    reference: ?*User,
};

fn make_error() !i32 {
    return error.OutOfMemory;
}

test "stringify - bool - true" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value = true;
    const actual = try stringify(aa, value);
    try std.testing.expect(std.mem.eql(u8, actual, ": bool = true"));
}

test "stringify - bool - false" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value = false;
    const actual = try stringify(aa, value);
    try std.testing.expect(std.mem.eql(u8, actual, ": bool = false"));
}

test "stringify - comptime_int" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value = 100;
    const actual = try stringify(aa, value);
    try std.testing.expect(std.mem.eql(u8, actual, ": comptime_int = 100"));
}

test "stringify - comptime_float" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value = 1.234;
    const actual = try stringify(aa, value);
    try std.testing.expect(std.mem.eql(u8, actual, ": comptime_float = 1.234"));
}

test "stringify - i32" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value: i32 = 200;
    const actual = try stringify(aa, value);
    try std.testing.expect(std.mem.eql(u8, actual, ": i32 = 200"));
}

test "stringify - f64" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value: f64 = 3.456;
    const actual = try stringify(aa, value);
    try std.testing.expect(std.mem.eql(u8, actual, ": f64 = 3.456"));
}

test "stringify - string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value = "foo";
    const actual = try stringify(aa, value);
    try std.testing.expect(std.mem.eql(u8, actual, ": []u8 = foo"));
}

test "stringify - array - bool" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value: [4]bool = .{ true, false, true, false };
    const actual = try stringify(aa, value);
    const expected =
        \\[
        \\  : bool = true
        \\  : bool = false
        \\  : bool = true
        \\  : bool = false
        \\]
    ;
    try std.testing.expect(std.mem.eql(u8, actual, expected));
}

test "stringify - array - i16" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value: [3]u16 = .{ 11, 22, 33 };
    const actual = try stringify(aa, value);
    const expected =
        \\[
        \\  : u16 = 11
        \\  : u16 = 22
        \\  : u16 = 33
        \\]
    ;
    try std.testing.expect(std.mem.eql(u8, actual, expected));
}

test "stringify - array - string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value: [2][]const u8 = .{ "foo", "bar" };
    const actual = try stringify(aa, value);
    const expected =
        \\[
        \\  : []u8 = foo
        \\  : []u8 = bar
        \\]
    ;
    try std.testing.expect(std.mem.eql(u8, actual, expected));
}

test "stringify - enum" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value: Foo = .Qua;
    const actual = try stringify(aa, value);
    const expected =
        \\: root.Foo = Qua
    ;
    try std.testing.expect(std.mem.eql(u8, actual, expected));
}

test "stringify - enumliteral" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value = .Baz;
    const actual = try stringify(aa, value);
    const expected =
        \\: @EnumLiteral() = .Baz
    ;
    try std.testing.expect(std.mem.eql(u8, actual, expected));
}

test "stringify - union - i32" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value: Shape = Shape{ .Circle = 100 };
    const actual = try stringify(aa, value);
    const expected =
        \\: root.Shape = Circle.{ .Circle = 100 }
    ;
    try std.testing.expect(std.mem.eql(u8, actual, expected));
}

test "stringify - union - struct" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value: Shape = Shape{ .Rectangle = Rectangle{ .h = 10, .w = 20 } };
    const actual = try stringify(aa, value);
    const expected =
        \\: root.Shape = Rectangle.{ .Rectangle = .{ .w = 20, .h = 10 } }
    ;
    try std.testing.expect(std.mem.eql(u8, actual, expected));
}

test "stringify - error set" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value = error.OutOfMemory;
    const actual = try stringify(aa, value);
    const expected =
        \\: error{OutOfMemory} = error.OutOfMemory
    ;
    try std.testing.expect(std.mem.eql(u8, actual, expected));
}

test "stringify - error union" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value = make_error();
    const actual = try stringify(aa, value);
    const expected =
        \\: !i32 = error.OutOfMemory
    ;
    try std.testing.expect(std.mem.eql(u8, actual, expected));
}

test "stringify - optional - i64" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value: ?i64 = 123;
    const actual = try stringify(aa, value);
    const expected =
        \\: ?i64 = 123
    ;
    try std.testing.expect(std.mem.eql(u8, actual, expected));
}

test "stringify - optional - null" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value: ?i64 = null;
    const actual = try stringify(aa, value);
    const expected =
        \\: ?i64 = null
    ;
    // print(">>{s}<<\n", .{actual});
    // print(">>{s}<<\n", .{expected});
    try std.testing.expect(std.mem.eql(u8, actual, expected));
}

test "expects - bool - true - success" {
    const actual = true;
    const expected = true;
    try expect(std.testing.allocator, @src(), expected, actual);
}

test "expects - bool - false - success" {
    const actual = false;
    const expected = false;
    try expect(std.testing.allocator, @src(), expected, actual);
}

test "expects - bool - failure" {
    const actual = true;
    const expected = false;
    const result = expect(std.testing.allocator, @src(), expected, actual);

    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "expects - i32 - success" {
    const actual: i32 = 1001;
    const expected: i32 = 1001;
    try expect(std.testing.allocator, @src(), expected, actual);
}

test "expects - i32 - failure" {
    const actual = 123456;
    const expected = 654321;
    const result = expect(std.testing.allocator, @src(), expected, actual);

    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "build_snapshot_name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const actual = try build_snapshot_name(aa, @src(), "fake_root");
    const expected = "fake_root/root_zig_root_test_build_snapshot_name.snap";
    try std.testing.expect(std.mem.eql(u8, expected, actual));
}

test "build_snapshot_name with spaces" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const actual = try build_snapshot_name(aa, @src(), "fake_root");
    const expected = "fake_root/root_zig_root_test_build_snapshot_name_with_spaces.snap";
    try std.testing.expect(std.mem.eql(u8, expected, actual));
}

test "compare - bool - true - success" {
    const data: bool = true;
    try compare(std.testing.io, std.testing.allocator, @src(), data);
}

test "compare - i32 - success" {
    const data: i32 = 11223344;
    try compare(std.testing.io, std.testing.allocator, @src(), data);
}

test "compare - i32 - failure" {
    // NOTE: This failure test only works if the snapshot has different value
    const data: i32 = 1122334457;
    const result = compare(std.testing.io, std.testing.allocator, @src(), data);
    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "compare - array - success" {
    const data = [5]f32{ 1.23, 2.34, 3.45, 4.56, 5.67 };
    try compare(std.testing.io, std.testing.allocator, @src(), data);
}

test "compare - struct - anonymous - success" {
    const data = .{
        .foo = 100,
        .bar = 200.345,
        .baz = false,
        .qua = [3]u16{ 11, 22, 33 },
        .quux = .{
            .abc = "this",
            .def = "is",
            .ghi = "a",
            .jkl = "test",
        },
        .prop1 = .Bar,
        .prop2 = Foo.Bar,
    };
    try compare(std.testing.io, std.testing.allocator, @src(), data);
}

test "compare - struct - User - success" {
    const data = User{
        .name = "Alice",
        .age = 99,
        .enabled = true,
        .favorite_shape = .{ .Circle = 200 },
        .ids = &[_]i8{ 1, 2, 3 },
        .reference = null,
    };

    try compare(std.testing.io, std.testing.allocator, @src(), data);
}

// Snapper module
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Io = std.Io;
const print = std.debug.print;

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

    // header for complex objects
    switch (ti) {
        .array => {
            try results.append(
                aa,
                try std.fmt.allocPrint(aa, "{s}[", .{
                    indent_s,
                }),
            );
        },
        .@"struct" => {
            try results.append(
                aa,
                try std.fmt.allocPrint(aa, "{s}{{", .{
                    indent_s,
                }),
            );
        },
        else => {},
    }

    // contents
    switch (ti) {
        .bool => {
            try results.append(
                aa,
                try std.fmt.allocPrint(aa, "{s}{any} <{any}>", .{
                    indent_s,
                    value,
                    @TypeOf(value),
                }),
            );
        },
        .int,
        .float,
        .comptime_int,
        .comptime_float,
        => {
            try results.append(
                aa,
                try std.fmt.allocPrint(aa, "{s}{d} <{any}>", .{
                    indent_s,
                    value,
                    @TypeOf(value),
                }),
            );
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
                            try std.fmt.allocPrint(aa, "{s}{s} <[]u8>", .{
                                indent_s,
                                value,
                            }),
                        );
                    } else {
                        // treat as not string
                        try results.append(
                            aa,
                            try std.fmt.allocPrint(aa, "{s}{any} <[]u8>", .{
                                indent_s,
                                value,
                            }),
                        );
                    }
                },
                else => {
                    // Unsupport datatype
                    // NOTE: When this pops up, figure out how to address
                    try results.append(
                        aa,
                        try std.fmt.allocPrint(
                            aa,
                            "TODO: {any} <{any} {any}>",
                            .{ value, @TypeOf(value), p.size },
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
                            try std.fmt.allocPrint(aa, "{s}{s}: {any} <{any}>", .{
                                indent2_s,
                                x.field_names[i],
                                sub_value,
                                @TypeOf(@field(value, x.field_names[i])),
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
                            try std.fmt.allocPrint(aa, "{s}{s}: {d} <{any}>", .{
                                indent2_s,
                                x.field_names[i],
                                sub_value,
                                @TypeOf(@field(value, x.field_names[i])),
                            }),
                        );
                    },
                    else => {
                        // more complex value, name and value are on separate lines
                        try results.append(
                            aa,
                            try std.fmt.allocPrint(aa, "{s}{s}:", .{
                                indent2_s,
                                x.field_names[i],
                            }),
                        );

                        try stringify_inner(aa, sub_value, indent + 2, results);
                    },
                }
            }
        },
        else => {
            // Unsupport datatype
            // NOTE: When this pops up, figure out how to address
            try results.append(
                aa,
                try std.fmt.allocPrint(
                    aa,
                    "TODO: {any} <{any}>",
                    .{ value, @TypeOf(value) },
                ),
            );
        },
    }

    // footer for complex objects
    switch (ti) {
        .array => {
            try results.append(
                aa,
                try std.fmt.allocPrint(aa, "{s}]", .{
                    indent_s,
                }),
            );
        },
        .@"struct" => {
            try results.append(
                aa,
                try std.fmt.allocPrint(aa, "{s}}}", .{
                    indent_s,
                }),
            );
        },
        else => {},
    }
}

/// Stringify value
fn stringify(aa: Allocator, value: anytype) ![]u8 {
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
    const snapshot_base_name_prelim = try std.fmt.allocPrint(aa, "{s}_{s}_{s}", .{
        src.file,
        src.module,
        src.fn_name,
    });

    const sanitized1 = try aa.alloc(u8, snapshot_base_name_prelim.len);
    _ = std.mem.replace(u8, snapshot_base_name_prelim, ".", "_", sanitized1);

    const sanitized2 = try aa.alloc(u8, snapshot_base_name_prelim.len);
    _ = std.mem.replace(u8, sanitized1, " ", "_", sanitized2);

    const snapshot_base_name = sanitized2;
    const snapshot_name = try std.fmt.allocPrint(aa, "{s}.snap", .{
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

    const buffer_size = 10;
    const actual_s = try stringify(aa, actual);

    // TODO: find project root and/or allow customization of snapshots path
    const snapshot_root = "./snapshots";
    std.Io.Dir.createDir(std.Io.Dir.cwd(), io, snapshot_root, .default_dir) catch |e| {
        if (e == Io.Dir.CreateDirError.PathAlreadyExists) {} else {
            return e;
        }
    };

    const snapshot_name = try build_snapshot_name(aa, src, snapshot_root);

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

        const header_len = (try std.fmt.allocPrint(aa, "snapshot: {s}\n", .{snapshot_name})).len;
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
        var data: [buffer_size]u8 = undefined;
        var actual_index: usize = 0;
        while (true) {
            const x = try ri.readSliceShort(&data);

            if (actual_index > actual_s.len) {
                // NOTE: Don't return early, I want to show the difference
                // std.log.scoped(.compare).warn(
                //     "Size mismatch {d} {d} (start)\n",
                //     .{
                //         actual_index,
                //         actual_s.len,
                //     },
                // );
                // return error.TestExpectedEqual;
            }
            if (actual_index + x > actual_s.len) {
                // NOTE: Don't return early, I want to show the difference
                // std.log.scoped(.compare).warn(
                //     "Size mismatch {d} {d} (end)\n",
                //     .{
                //         actual_index + 1,
                //         actual_s.len,
                //     },
                // );
                // return error.TestExpectedEqual;
            }

            if (!std.mem.eql(u8, data[0..x], actual_s[actual_index .. actual_index + x])) {
                // failed match
                std.log.scoped(.compare).err(
                    "\nexpected: '{s}'\nactual  : '{s}'",
                    .{
                        data[0..x],
                        actual_s[actual_index .. actual_index + x],
                    },
                );
                return error.TestExpectedEqual;
            }
            actual_index += x;

            if (x < buffer.len) break;
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

test "stringify - bool - true" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value = true;
    const actual = try stringify(aa, value);
    try std.testing.expect(std.mem.eql(u8, actual, "true <bool>"));
}

test "stringify - bool - false" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value = false;
    const actual = try stringify(aa, value);
    try std.testing.expect(std.mem.eql(u8, actual, "false <bool>"));
}

test "stringify - comptime_int" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value = 100;
    const actual = try stringify(aa, value);
    try std.testing.expect(std.mem.eql(u8, actual, "100 <comptime_int>"));
}

test "stringify - comptime_float" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value = 1.234;
    const actual = try stringify(aa, value);
    try std.testing.expect(std.mem.eql(u8, actual, "1.234 <comptime_float>"));
}

test "stringify - i32" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value: i32 = 200;
    const actual = try stringify(aa, value);
    try std.testing.expect(std.mem.eql(u8, actual, "200 <i32>"));
}

test "stringify - f64" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value: f64 = 3.456;
    const actual = try stringify(aa, value);
    try std.testing.expect(std.mem.eql(u8, actual, "3.456 <f64>"));
}

test "stringify - string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value = "foo";
    const actual = try stringify(aa, value);
    try std.testing.expect(std.mem.eql(u8, actual, "foo <[]u8>"));
}

test "stringify - array - bool" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const value: [4]bool = .{ true, false, true, false };
    const actual = try stringify(aa, value);
    const expected =
        \\[
        \\  true <bool>
        \\  false <bool>
        \\  true <bool>
        \\  false <bool>
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
        \\  11 <u16>
        \\  22 <u16>
        \\  33 <u16>
        \\]
    ;
    // print(">>{s}<<\n", .{actual});
    // print(">>{s}<<\n", .{expected});
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
        \\  foo <[]u8>
        \\  bar <[]u8>
        \\]
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
    const data: i32 = 11223344;
    const result = compare(std.testing.io, std.testing.allocator, @src(), data);
    try std.testing.expectError(error.TestExpectedEqual, result);
}

test "compare - array - success" {
    const data = [5]f32{ 1.23, 2.34, 3.45, 4.56, 5.67 };
    try compare(std.testing.io, std.testing.allocator, @src(), data);
}

test "compare - struct - success" {
    const data = .{
        .foo = 100,
        .bar = 200.300,
        .baz = false,
        .qua = [3]u16{ 11, 22, 33 },
        .quux = .{
            .abc = "this",
            .def = "is",
            .ghi = "a",
            .jkl = "test",
        },
    };
    try compare(std.testing.io, std.testing.allocator, @src(), data);
}

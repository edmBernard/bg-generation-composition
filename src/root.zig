//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;
const zsvg = @import("zsvg");

pub const canvas_size = 2000;
pub const legacy_grid_size = 15;
pub const square_size = 80;
pub const gap_size = 40;
pub const background_hex = 0xf5f0e6;
pub const square_hex = 0x000000;
pub const default_pattern_path = "pattern.txt";
pub const default_export_path = "pattern.svg";

pub const legacy_pattern_text_line_len = (legacy_grid_size * 2) - 1;
pub const legacy_pattern_text_len = legacy_grid_size * (legacy_pattern_text_line_len + 1);

const target_grid_span = (square_size * legacy_grid_size) + (gap_size * (legacy_grid_size - 1));
const target_grid_offset = @divTrunc(canvas_size - target_grid_span, 2);

pub const Point = struct {
    x: f32,
    y: f32,
};

pub const Layout = struct {
    size: usize,
    square_extent: f32,
    gap_extent: f32,
    pitch: f32,
    span: f32,
    offset: f32,
};

pub const TilePolygon = struct {
    len: u8,
    points: [5]Point,
};

pub const Triangle = struct {
    points: [3]Point,
};

pub const TileTriangles = struct {
    len: u8,
    triangles: [3]Triangle,
};

pub const Pattern = struct {
    allocator: std.mem.Allocator,
    size: usize,
    tiles: []u4,

    pub fn init(allocator: std.mem.Allocator, size: usize) !Pattern {
        if (size == 0) return error.InvalidPatternSize;
        const tiles = try allocator.alloc(u4, size * size);
        @memset(tiles, 0);
        return .{
            .allocator = allocator,
            .size = size,
            .tiles = tiles,
        };
    }

    pub fn clone(self: Pattern, allocator: std.mem.Allocator) !Pattern {
        const copy = try Pattern.init(allocator, self.size);
        @memcpy(copy.tiles, self.tiles);
        return copy;
    }

    pub fn deinit(self: *Pattern) void {
        self.allocator.free(self.tiles);
        self.tiles = &.{};
        self.size = 0;
    }

    pub fn eql(self: Pattern, other: Pattern) bool {
        return self.size == other.size and std.mem.eql(u4, self.tiles, other.tiles);
    }

    pub fn get(self: Pattern, row: usize, col: usize) u4 {
        return self.tiles[(row * self.size) + col];
    }

    pub fn set(self: *Pattern, row: usize, col: usize, value: u4) void {
        self.tiles[(row * self.size) + col] = value;
    }

    pub fn resized(self: Pattern, allocator: std.mem.Allocator, new_size: usize) !Pattern {
        var resized_pattern = try Pattern.init(allocator, new_size);
        const overlap = @min(self.size, new_size);
        for (0..overlap) |row| {
            for (0..overlap) |col| {
                resized_pattern.set(row, col, self.get(row, col));
            }
        }
        return resized_pattern;
    }
};

pub const PatternParseError = error{
    InvalidPatternRowCount,
    InvalidPatternColumnCount,
    InvalidPatternSeparator,
    InvalidPatternDigit,
    InvalidPatternSize,
};

const default_pattern_text =
    \\0 0 0 0 0 0 0 2 0 0 0 0 0 0 0
    \\0 0 0 0 0 0 5 0 6 0 0 0 0 0 0
    \\0 0 0 0 0 1 0 2 0 6 0 0 0 0 0
    \\0 0 0 0 5 0 5 0 2 0 2 0 0 0 0
    \\0 0 0 1 0 5 0 2 0 6 0 2 0 0 0
    \\0 0 5 0 5 0 5 0 6 0 2 0 6 0 0
    \\0 5 0 0 0 1 0 1 0 6 0 6 0 6 0
    \\1 0 1 0 1 0 1 0 3 0 3 0 3 0 3
    \\0 8 0 8 0 0 0 8 0 7 0 7 0 4 0
    \\0 0 4 0 8 0 4 0 4 0 4 0 7 0 0
    \\0 0 0 8 0 1 0 8 0 7 0 7 0 0 0
    \\0 0 0 0 8 0 0 0 4 0 3 0 0 0 0
    \\0 0 0 0 0 4 0 8 0 7 0 0 0 0 0
    \\0 0 0 0 0 0 8 0 4 0 0 0 0 0 0
    \\0 0 0 0 0 0 0 8 0 0 0 0 0 0 0
;

pub fn loadPattern(allocator: std.mem.Allocator, path: []const u8) !Pattern {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    return loadPatternWithIo(allocator, threaded.io(), path);
}

pub fn savePattern(pattern: Pattern, path: []const u8) !void {
    var threaded = std.Io.Threaded.init(std.heap.smp_allocator, .{});
    defer threaded.deinit();
    return savePatternWithIo(std.heap.smp_allocator, threaded.io(), pattern, path);
}

pub fn buildGridDocumentFromPattern(allocator: std.mem.Allocator, pattern: Pattern) !zsvg.Document {
    var doc: zsvg.Document = .init(
        allocator,
        canvas_size,
        canvas_size,
        .fromHex(background_hex),
    );
    errdefer doc.deinit();

    const fill = zsvg.Fill.solidHex(square_hex);

    for (0..pattern.size) |row| {
        for (0..pattern.size) |col| {
            const polygon = tilePolygonForCell(row, col, pattern.size, pattern.get(row, col));
            try addPolygonToDocument(&doc, polygon, fill);
        }
    }

    return doc;
}

pub fn saveGridSvgFromPattern(
    allocator: std.mem.Allocator,
    io: std.Io,
    pattern: Pattern,
    path: []const u8,
) !void {
    var doc = try buildGridDocumentFromPattern(allocator, pattern);
    defer doc.deinit();
    try doc.save(allocator, io, path);
}

pub fn writeGridSvg(allocator: std.mem.Allocator, writer: *Io.Writer) !void {
    var pattern = try loadPattern(allocator, default_pattern_path);
    defer pattern.deinit();

    var doc = try buildGridDocumentFromPattern(allocator, pattern);
    defer doc.deinit();
    try doc.writeTo(writer);
}

pub fn saveGridSvg(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    var pattern = try loadPatternWithIo(allocator, io, default_pattern_path);
    defer pattern.deinit();
    try saveGridSvgFromPattern(allocator, io, pattern, path);
}

pub fn gridLayout(size: usize) Layout {
    std.debug.assert(size > 0);

    const span_target: f32 = @floatFromInt(target_grid_span);
    const denominator = @as(f32, @floatFromInt((size * 3) - 1));
    const gap_extent = span_target / denominator;
    const square_extent = gap_extent * 2.0;
    const span = (square_extent * @as(f32, @floatFromInt(size))) +
        (gap_extent * @as(f32, @floatFromInt(size - 1)));
    const offset = (@as(f32, @floatFromInt(canvas_size)) - span) / 2.0;

    return .{
        .size = size,
        .square_extent = square_extent,
        .gap_extent = gap_extent,
        .pitch = square_extent + gap_extent,
        .span = span,
        .offset = offset,
    };
}

pub fn tilePolygonForCell(row: usize, col: usize, size: usize, tile: u4) TilePolygon {
    const layout = gridLayout(size);
    const x = layout.offset + (@as(f32, @floatFromInt(col)) * layout.pitch);
    const y = layout.offset + (@as(f32, @floatFromInt(row)) * layout.pitch);
    return tilePolygon(tile, x, y, layout.square_extent);
}

pub fn tilePolygon(tile: u4, x: f32, y: f32, extent: f32) TilePolygon {
    return switch (tile) {
        0 => .{
            .len = 4,
            .points = .{
                .{ .x = x, .y = y },
                .{ .x = x + extent, .y = y },
                .{ .x = x + extent, .y = y + extent },
                .{ .x = x, .y = y + extent },
                undefined,
            },
        },
        1 => .{
            .len = 5,
            .points = .{
                .{ .x = x, .y = y },
                .{ .x = x + extent, .y = y },
                .{ .x = x + extent / 2, .y = y + extent / 2 },
                .{ .x = x + extent, .y = y + extent },
                .{ .x = x, .y = y + extent },
            },
        },
        2 => .{
            .len = 5,
            .points = .{
                .{ .x = x, .y = y },
                .{ .x = x + extent, .y = y },
                .{ .x = x + extent, .y = y + extent },
                .{ .x = x + extent / 2, .y = y + extent / 2 },
                .{ .x = x, .y = y + extent },
            },
        },
        3 => .{
            .len = 5,
            .points = .{
                .{ .x = x, .y = y },
                .{ .x = x + extent, .y = y },
                .{ .x = x + extent, .y = y + extent },
                .{ .x = x, .y = y + extent },
                .{ .x = x + extent / 2, .y = y + extent / 2 },
            },
        },
        4 => .{
            .len = 5,
            .points = .{
                .{ .x = x, .y = y },
                .{ .x = x + extent / 2, .y = y + extent / 2 },
                .{ .x = x + extent, .y = y },
                .{ .x = x + extent, .y = y + extent },
                .{ .x = x, .y = y + extent },
            },
        },
        5 => .{
            .len = 3,
            .points = .{
                .{ .x = x, .y = y },
                .{ .x = x + extent, .y = y },
                .{ .x = x, .y = y + extent },
                undefined,
                undefined,
            },
        },
        6 => .{
            .len = 3,
            .points = .{
                .{ .x = x, .y = y },
                .{ .x = x + extent, .y = y },
                .{ .x = x + extent, .y = y + extent },
                undefined,
                undefined,
            },
        },
        7 => .{
            .len = 3,
            .points = .{
                .{ .x = x + extent, .y = y },
                .{ .x = x + extent, .y = y + extent },
                .{ .x = x, .y = y + extent },
                undefined,
                undefined,
            },
        },
        8 => .{
            .len = 3,
            .points = .{
                .{ .x = x, .y = y },
                .{ .x = x + extent, .y = y + extent },
                .{ .x = x, .y = y + extent },
                undefined,
                undefined,
            },
        },
        else => .{
            .len = 4,
            .points = .{
                .{ .x = x, .y = y },
                .{ .x = x + extent, .y = y },
                .{ .x = x + extent, .y = y + extent },
                .{ .x = x, .y = y + extent },
                undefined,
            },
        },
    };
}

pub fn tileTrianglesForCell(row: usize, col: usize, size: usize, tile: u4) TileTriangles {
    const layout = gridLayout(size);
    const x = layout.offset + (@as(f32, @floatFromInt(col)) * layout.pitch);
    const y = layout.offset + (@as(f32, @floatFromInt(row)) * layout.pitch);
    return tileTriangles(tile, x, y, layout.square_extent);
}

pub fn tileTriangles(tile: u4, x: f32, y: f32, extent: f32) TileTriangles {
    const tl: Point = .{ .x = x, .y = y };
    const tr: Point = .{ .x = x + extent, .y = y };
    const br: Point = .{ .x = x + extent, .y = y + extent };
    const bl: Point = .{ .x = x, .y = y + extent };
    const center: Point = .{ .x = x + extent / 2, .y = y + extent / 2 };

    return switch (tile) {
        0 => .{
            .len = 2,
            .triangles = .{
                .{ .points = .{ tl, tr, br } },
                .{ .points = .{ tl, br, bl } },
                undefined,
            },
        },
        1 => .{
            .len = 3,
            .triangles = .{
                .{ .points = .{ tl, tr, center } },
                .{ .points = .{ tl, center, bl } },
                .{ .points = .{ bl, center, br } },
            },
        },
        2 => .{
            .len = 3,
            .triangles = .{
                .{ .points = .{ tl, tr, center } },
                .{ .points = .{ tr, br, center } },
                .{ .points = .{ tl, center, bl } },
            },
        },
        3 => .{
            .len = 3,
            .triangles = .{
                .{ .points = .{ tl, tr, center } },
                .{ .points = .{ center, tr, br } },
                .{ .points = .{ center, br, bl } },
            },
        },
        4 => .{
            .len = 3,
            .triangles = .{
                .{ .points = .{ tl, center, bl } },
                .{ .points = .{ center, tr, br } },
                .{ .points = .{ bl, center, br } },
            },
        },
        5 => .{
            .len = 1,
            .triangles = .{
                .{ .points = .{ tl, tr, bl } },
                undefined,
                undefined,
            },
        },
        6 => .{
            .len = 1,
            .triangles = .{
                .{ .points = .{ tl, tr, br } },
                undefined,
                undefined,
            },
        },
        7 => .{
            .len = 1,
            .triangles = .{
                .{ .points = .{ tr, br, bl } },
                undefined,
                undefined,
            },
        },
        8 => .{
            .len = 1,
            .triangles = .{
                .{ .points = .{ tl, br, bl } },
                undefined,
                undefined,
            },
        },
        else => tileTriangles(0, x, y, extent),
    };
}

fn addPolygonToDocument(doc: *zsvg.Document, polygon: TilePolygon, fill: zsvg.Fill) !void {
    switch (polygon.len) {
        3 => {
            const points: [3]zsvg.Point = .{
                .{ .x = polygon.points[0].x, .y = polygon.points[0].y },
                .{ .x = polygon.points[1].x, .y = polygon.points[1].y },
                .{ .x = polygon.points[2].x, .y = polygon.points[2].y },
            };
            try doc.addShape(points, .{ .fill = fill });
        },
        4 => {
            const points: [4]zsvg.Point = .{
                .{ .x = polygon.points[0].x, .y = polygon.points[0].y },
                .{ .x = polygon.points[1].x, .y = polygon.points[1].y },
                .{ .x = polygon.points[2].x, .y = polygon.points[2].y },
                .{ .x = polygon.points[3].x, .y = polygon.points[3].y },
            };
            try doc.addShape(points, .{ .fill = fill });
        },
        5 => {
            const points: [5]zsvg.Point = .{
                .{ .x = polygon.points[0].x, .y = polygon.points[0].y },
                .{ .x = polygon.points[1].x, .y = polygon.points[1].y },
                .{ .x = polygon.points[2].x, .y = polygon.points[2].y },
                .{ .x = polygon.points[3].x, .y = polygon.points[3].y },
                .{ .x = polygon.points[4].x, .y = polygon.points[4].y },
            };
            try doc.addShape(points, .{ .fill = fill });
        },
        else => unreachable,
    }
}

fn loadPatternWithIo(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Pattern {
    const contents = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024));
    defer allocator.free(contents);
    return parsePatternText(allocator, contents);
}

fn savePatternWithIo(
    allocator: std.mem.Allocator,
    io: std.Io,
    pattern: Pattern,
    path: []const u8,
) !void {
    const serialized = try serializePattern(allocator, pattern);
    defer allocator.free(serialized);

    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = serialized,
    });
}

fn parsePatternText(allocator: std.mem.Allocator, text: []const u8) !Pattern {
    const trimmed = if (text.len > 0 and text[text.len - 1] == '\n') text[0 .. text.len - 1] else text;
    if (trimmed.len == 0) return error.InvalidPatternRowCount;

    var line_iter = std.mem.splitScalar(u8, trimmed, '\n');
    const first_line = line_iter.next() orelse return error.InvalidPatternRowCount;

    var declared_size: usize = legacy_grid_size;
    var first_row: ?[]const u8 = first_line;
    if (std.mem.startsWith(u8, first_line, "size=")) {
        declared_size = std.fmt.parseInt(usize, first_line["size=".len..], 10) catch return error.InvalidPatternSize;
        if (declared_size == 0) return error.InvalidPatternSize;
        first_row = null;
    }

    var pattern = try Pattern.init(allocator, declared_size);
    errdefer pattern.deinit();

    var row: usize = 0;
    if (first_row) |line| {
        try parsePatternRow(&pattern, row, line);
        row += 1;
    }

    while (line_iter.next()) |line| {
        if (row >= pattern.size) return error.InvalidPatternRowCount;
        try parsePatternRow(&pattern, row, line);
        row += 1;
    }

    if (row != pattern.size) return error.InvalidPatternRowCount;
    return pattern;
}

fn parsePatternRow(pattern: *Pattern, row: usize, line: []const u8) !void {
    if (line.len != expectedPatternLineLen(pattern.size)) return error.InvalidPatternColumnCount;

    for (0..pattern.size) |col| {
        const char_index = col * 2;
        const digit = line[char_index];
        if (digit < '0' or digit > '8') return error.InvalidPatternDigit;
        pattern.set(row, col, @intCast(digit - '0'));

        if (col + 1 < pattern.size and line[char_index + 1] != ' ') {
            return error.InvalidPatternSeparator;
        }
    }
}

fn serializePattern(allocator: std.mem.Allocator, pattern: Pattern) ![]u8 {
    const header = try std.fmt.allocPrint(allocator, "size={d}\n", .{pattern.size});
    defer allocator.free(header);

    const line_len = expectedPatternLineLen(pattern.size);
    const body_len = pattern.size * (line_len + 1);
    const output = try allocator.alloc(u8, header.len + body_len);

    @memcpy(output[0..header.len], header);

    var index = header.len;
    for (0..pattern.size) |row| {
        for (0..pattern.size) |col| {
            output[index] = @as(u8, '0') + pattern.get(row, col);
            index += 1;

            if (col + 1 < pattern.size) {
                output[index] = ' ';
                index += 1;
            }
        }
        output[index] = '\n';
        index += 1;
    }

    return output;
}

fn expectedPatternLineLen(size: usize) usize {
    return (size * 2) - 1;
}

fn legacyPattern(allocator: std.mem.Allocator) !Pattern {
    const pattern = try Pattern.init(allocator, legacy_grid_size);
    const legacy_tiles = [_]u4{
        0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 5, 0, 6, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 1, 0, 2, 0, 6, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 5, 0, 5, 0, 2, 0, 2, 0, 0, 0, 0,
        0, 0, 0, 1, 0, 5, 0, 2, 0, 6, 0, 2, 0, 0, 0,
        0, 0, 5, 0, 5, 0, 5, 0, 6, 0, 2, 0, 6, 0, 0,
        0, 5, 0, 0, 0, 1, 0, 1, 0, 6, 0, 6, 0, 6, 0,
        1, 0, 1, 0, 1, 0, 1, 0, 3, 0, 3, 0, 3, 0, 3,
        0, 8, 0, 8, 0, 0, 0, 8, 0, 7, 0, 7, 0, 4, 0,
        0, 0, 4, 0, 8, 0, 4, 0, 4, 0, 4, 0, 7, 0, 0,
        0, 0, 0, 8, 0, 1, 0, 8, 0, 7, 0, 7, 0, 0, 0,
        0, 0, 0, 0, 8, 0, 0, 0, 4, 0, 3, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 4, 0, 8, 0, 7, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 8, 0, 4, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0,
    };
    @memcpy(pattern.tiles, &legacy_tiles);
    return pattern;
}

test "grid geometry stays centered for legacy layout" {
    const layout = gridLayout(legacy_grid_size);
    try std.testing.expectApproxEqAbs(@as(f32, 1760.0), layout.span, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 120.0), layout.offset, 0.01);
}

test "grid geometry stays centered for multiple sizes" {
    for ([_]usize{ 10, 15, 20 }) |size| {
        const layout = gridLayout(size);
        try std.testing.expectApproxEqAbs(@as(f32, 1760.0), layout.span, 0.05);
        try std.testing.expectApproxEqAbs(
            (@as(f32, @floatFromInt(canvas_size)) - layout.span) / 2.0,
            layout.offset,
            0.05,
        );
    }
}

test "pattern text parses expected tile values" {
    var pattern = try parsePatternText(std.testing.allocator, default_pattern_text);
    defer pattern.deinit();

    try std.testing.expectEqual(@as(usize, legacy_grid_size), pattern.size);
    try std.testing.expectEqual(@as(u4, 2), pattern.get(0, 7));
    try std.testing.expectEqual(@as(u4, 5), pattern.get(3, 4));
    try std.testing.expectEqual(@as(u4, 8), pattern.get(14, 7));
}

test "pattern parser reads explicit size headers" {
    const text =
        \\size=3
        \\0 1 2
        \\3 4 5
        \\6 7 8
    ;
    var pattern = try parsePatternText(std.testing.allocator, text);
    defer pattern.deinit();

    try std.testing.expectEqual(@as(usize, 3), pattern.size);
    try std.testing.expectEqual(@as(u4, 4), pattern.get(1, 1));
}

test "pattern parser rejects invalid size header" {
    const text =
        \\size=nope
        \\0 1 2
        \\3 4 5
        \\6 7 8
    ;
    try std.testing.expectError(error.InvalidPatternSize, parsePatternText(std.testing.allocator, text));
}

test "pattern parser rejects invalid digit" {
    const bad_text =
        \\0 0 0 0 0 0 0 2 0 0 0 0 0 0 0
        \\0 0 0 0 0 0 5 0 6 0 0 0 0 0 9
        \\0 0 0 0 0 1 0 2 0 6 0 0 0 0 0
        \\0 0 0 0 5 0 5 0 2 0 2 0 0 0 0
        \\0 0 0 1 0 5 0 2 0 6 0 2 0 0 0
        \\0 0 5 0 5 0 5 0 6 0 2 0 6 0 0
        \\0 5 0 0 0 1 0 1 0 6 0 6 0 6 0
        \\1 0 1 0 1 0 1 0 3 0 3 0 3 0 3
        \\0 8 0 8 0 0 0 8 0 7 0 7 0 4 0
        \\0 0 4 0 8 0 4 0 4 0 4 0 7 0 0
        \\0 0 0 8 0 1 0 8 0 7 0 7 0 0 0
        \\0 0 0 0 8 0 0 0 4 0 3 0 0 0 0
        \\0 0 0 0 0 4 0 8 0 7 0 0 0 0 0
        \\0 0 0 0 0 0 8 0 4 0 0 0 0 0 0
        \\0 0 0 0 0 0 0 8 0 0 0 0 0 0 0
    ;
    try std.testing.expectError(error.InvalidPatternDigit, parsePatternText(std.testing.allocator, bad_text));
}

test "pattern parser rejects missing row" {
    const bad_text =
        \\0 0 0 0 0 0 0 2 0 0 0 0 0 0 0
        \\0 0 0 0 0 0 5 0 6 0 0 0 0 0 0
        \\0 0 0 0 0 1 0 2 0 6 0 0 0 0 0
        \\0 0 0 0 5 0 5 0 2 0 2 0 0 0 0
        \\0 0 0 1 0 5 0 2 0 6 0 2 0 0 0
        \\0 0 5 0 5 0 5 0 6 0 2 0 6 0 0
        \\0 5 0 0 0 1 0 1 0 6 0 6 0 6 0
        \\1 0 1 0 1 0 1 0 3 0 3 0 3 0 3
        \\0 8 0 8 0 0 0 8 0 7 0 7 0 4 0
        \\0 0 4 0 8 0 4 0 4 0 4 0 7 0 0
        \\0 0 0 8 0 1 0 8 0 7 0 7 0 0 0
        \\0 0 0 0 8 0 0 0 4 0 3 0 0 0 0
        \\0 0 0 0 0 4 0 8 0 7 0 0 0 0 0
        \\0 0 0 0 0 0 8 0 4 0 0 0 0 0 0
    ;
    try std.testing.expectError(error.InvalidPatternRowCount, parsePatternText(std.testing.allocator, bad_text));
}

test "pattern parser rejects missing column" {
    const bad_text =
        \\0 0 0 0 0 0 0 2 0 0 0 0 0 0
        \\0 0 0 0 0 0 5 0 6 0 0 0 0 0 0
        \\0 0 0 0 0 1 0 2 0 6 0 0 0 0 0
        \\0 0 0 0 5 0 5 0 2 0 2 0 0 0 0
        \\0 0 0 1 0 5 0 2 0 6 0 2 0 0 0
        \\0 0 5 0 5 0 5 0 6 0 2 0 6 0 0
        \\0 5 0 0 0 1 0 1 0 6 0 6 0 6 0
        \\1 0 1 0 1 0 1 0 3 0 3 0 3 0 3
        \\0 8 0 8 0 0 0 8 0 7 0 7 0 4 0
        \\0 0 4 0 8 0 4 0 4 0 4 0 7 0 0
        \\0 0 0 8 0 1 0 8 0 7 0 7 0 0 0
        \\0 0 0 0 8 0 0 0 4 0 3 0 0 0 0
        \\0 0 0 0 0 4 0 8 0 7 0 0 0 0 0
        \\0 0 0 0 0 0 8 0 4 0 0 0 0 0 0
        \\0 0 0 0 0 0 0 8 0 0 0 0 0 0 0
    ;
    try std.testing.expectError(error.InvalidPatternColumnCount, parsePatternText(std.testing.allocator, bad_text));
}

test "pattern serialization round trips" {
    var parsed = try parsePatternText(std.testing.allocator, default_pattern_text);
    defer parsed.deinit();

    const serialized = try serializePattern(std.testing.allocator, parsed);
    defer std.testing.allocator.free(serialized);

    var reparsed = try parsePatternText(std.testing.allocator, serialized);
    defer reparsed.deinit();

    try std.testing.expect(parsed.eql(reparsed));
}

test "pattern resizing keeps top-left cells and fills new cells with zero" {
    const text =
        \\size=2
        \\1 2
        \\3 4
    ;
    var pattern = try parsePatternText(std.testing.allocator, text);
    defer pattern.deinit();

    var grown = try pattern.resized(std.testing.allocator, 4);
    defer grown.deinit();

    try std.testing.expectEqual(@as(u4, 1), grown.get(0, 0));
    try std.testing.expectEqual(@as(u4, 4), grown.get(1, 1));
    try std.testing.expectEqual(@as(u4, 0), grown.get(3, 3));
}

test "pattern resizing crops from the bottom-right when shrinking" {
    const text =
        \\size=3
        \\1 2 3
        \\4 5 6
        \\7 8 0
    ;
    var pattern = try parsePatternText(std.testing.allocator, text);
    defer pattern.deinit();

    var shrunk = try pattern.resized(std.testing.allocator, 2);
    defer shrunk.deinit();

    try std.testing.expectEqual(@as(usize, 2), shrunk.size);
    try std.testing.expectEqual(@as(u4, 1), shrunk.get(0, 0));
    try std.testing.expectEqual(@as(u4, 5), shrunk.get(1, 1));
}

test "grid document contains 225 black shapes" {
    var pattern = try parsePatternText(std.testing.allocator, default_pattern_text);
    defer pattern.deinit();

    var doc = try buildGridDocumentFromPattern(std.testing.allocator, pattern);
    defer doc.deinit();

    const svg = try doc.toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(svg);

    var path_count: usize = 0;
    var search_from: usize = 0;
    while (std.mem.indexOfPos(u8, svg, search_from, "<path")) |index| {
        path_count += 1;
        search_from = index + 1;
    }

    try std.testing.expectEqual(@as(usize, legacy_grid_size * legacy_grid_size), path_count);
    try std.testing.expect(std.mem.indexOf(u8, svg, "fill='rgb(245,240,230)'") != null);
}

test "default pattern matches the legacy composition svg" {
    var current_pattern = try parsePatternText(std.testing.allocator, default_pattern_text);
    defer current_pattern.deinit();
    var old_pattern = try legacyPattern(std.testing.allocator);
    defer old_pattern.deinit();

    var current_doc = try buildGridDocumentFromPattern(std.testing.allocator, current_pattern);
    defer current_doc.deinit();
    var old_doc = try buildGridDocumentFromPattern(std.testing.allocator, old_pattern);
    defer old_doc.deinit();

    const current_svg = try current_doc.toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(current_svg);
    const old_svg = try old_doc.toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(old_svg);

    try std.testing.expectEqualStrings(old_svg, current_svg);
}

test "tile polygons expose expected vertex counts" {
    try std.testing.expectEqual(@as(u8, 4), tilePolygon(0, 0, 0, 10).len);
    try std.testing.expectEqual(@as(u8, 5), tilePolygon(1, 0, 0, 10).len);
    try std.testing.expectEqual(@as(u8, 5), tilePolygon(4, 0, 0, 10).len);
    try std.testing.expectEqual(@as(u8, 3), tilePolygon(5, 0, 0, 10).len);
    try std.testing.expectEqual(@as(u8, 3), tilePolygon(8, 0, 0, 10).len);
}

test "tile triangles expose expected triangle counts" {
    try std.testing.expectEqual(@as(u8, 2), tileTriangles(0, 0, 0, 10).len);
    try std.testing.expectEqual(@as(u8, 3), tileTriangles(1, 0, 0, 10).len);
    try std.testing.expectEqual(@as(u8, 3), tileTriangles(4, 0, 0, 10).len);
    try std.testing.expectEqual(@as(u8, 1), tileTriangles(5, 0, 0, 10).len);
    try std.testing.expectEqual(@as(u8, 1), tileTriangles(8, 0, 0, 10).len);
}

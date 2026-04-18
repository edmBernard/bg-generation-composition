//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;
const zsvg = @import("zsvg");

pub const canvas_size = 2000;
pub const grid_size = 15;
pub const square_size = 80;
pub const gap_size = 40;
pub const background_hex = 0xf5f0e6;
pub const square_hex = 0x000000;
pub const default_pattern_path = "pattern.txt";
pub const default_export_path = "pattern.svg";

pub const pattern_text_line_len = (grid_size * 2) - 1;
pub const pattern_text_len = grid_size * (pattern_text_line_len + 1);

pub const Point = struct {
    x: f32,
    y: f32,
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
    tiles: [grid_size * grid_size]u4,

    pub fn get(self: Pattern, row: usize, col: usize) u4 {
        return self.tiles[(row * grid_size) + col];
    }

    pub fn set(self: *Pattern, row: usize, col: usize, value: u4) void {
        self.tiles[(row * grid_size) + col] = value;
    }
};

pub const PatternParseError = error{
    InvalidPatternRowCount,
    InvalidPatternColumnCount,
    InvalidPatternSeparator,
    InvalidPatternDigit,
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
    // FIXME: we should pass io as an argument ?
    var threaded = std.Io.Threaded.init(std.heap.smp_allocator, .{});
    defer threaded.deinit();
    return savePatternWithIo(threaded.io(), pattern, path);
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

    for (0..grid_size) |row| {
        for (0..grid_size) |col| {
            const polygon = tilePolygonForCell(row, col, pattern.get(row, col));
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
    const pattern = try loadPattern(allocator, default_pattern_path);
    var doc = try buildGridDocumentFromPattern(allocator, pattern);
    defer doc.deinit();
    try doc.writeTo(writer);
}

pub fn saveGridSvg(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    const pattern = try loadPatternWithIo(allocator, io, default_pattern_path);
    try saveGridSvgFromPattern(allocator, io, pattern, path);
}

pub fn tilePolygonForCell(row: usize, col: usize, tile: u4) TilePolygon {
    const x: f32 = @floatFromInt(gridOffset() + (col * (square_size + gap_size)));
    const y: f32 = @floatFromInt(gridOffset() + (row * (square_size + gap_size)));
    const extent: f32 = @floatFromInt(square_size);
    return tilePolygon(tile, x, y, extent);
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

pub fn tileTrianglesForCell(row: usize, col: usize, tile: u4) TileTriangles {
    const x: f32 = @floatFromInt(gridOffset() + (col * (square_size + gap_size)));
    const y: f32 = @floatFromInt(gridOffset() + (row * (square_size + gap_size)));
    const extent: f32 = @floatFromInt(square_size);
    return tileTriangles(tile, x, y, extent);
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

fn gridOffset() usize {
    const grid_span = (square_size * grid_size) + (gap_size * (grid_size - 1));
    return @divTrunc(canvas_size - grid_span, 2);
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
    const contents = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(pattern_text_len + 64));
    defer allocator.free(contents);
    return parsePatternText(contents);
}

fn savePatternWithIo(io: std.Io, pattern: Pattern, path: []const u8) !void {
    const serialized = serializePattern(pattern);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = &serialized,
    });
}

fn parsePatternText(text: []const u8) PatternParseError!Pattern {
    const trimmed = if (text.len > 0 and text[text.len - 1] == '\n') text[0 .. text.len - 1] else text;
    var line_iter = std.mem.splitScalar(u8, trimmed, '\n');
    var pattern: Pattern = .{ .tiles = undefined };
    var row: usize = 0;

    while (line_iter.next()) |line| {
        if (row >= grid_size) return error.InvalidPatternRowCount;
        if (line.len != pattern_text_line_len) return error.InvalidPatternColumnCount;

        for (0..grid_size) |col| {
            const char_index = col * 2;
            const digit = line[char_index];
            if (digit < '0' or digit > '8') return error.InvalidPatternDigit;
            pattern.tiles[(row * grid_size) + col] = @intCast(digit - '0');

            if (col + 1 < grid_size and line[char_index + 1] != ' ') {
                return error.InvalidPatternSeparator;
            }
        }

        row += 1;
    }

    if (row != grid_size) return error.InvalidPatternRowCount;
    return pattern;
}

fn serializePattern(pattern: Pattern) [pattern_text_len]u8 {
    var buffer: [pattern_text_len]u8 = undefined;
    var index: usize = 0;

    for (0..grid_size) |row| {
        for (0..grid_size) |col| {
            buffer[index] = @as(u8, '0') + pattern.get(row, col);
            index += 1;

            if (col + 1 < grid_size) {
                buffer[index] = ' ';
                index += 1;
            }
        }
        buffer[index] = '\n';
        index += 1;
    }

    return buffer;
}

fn legacyPattern() Pattern {
    return .{
        .tiles = [grid_size * grid_size]u4{
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
        },
    };
}

test "grid geometry stays centered" {
    const grid_span = (square_size * grid_size) + (gap_size * (grid_size - 1));
    const offset = gridOffset();
    try std.testing.expectEqual(@as(usize, 1760), grid_span);
    try std.testing.expectEqual(@as(usize, 120), offset);
}

test "pattern text parses expected tile values" {
    const pattern = try parsePatternText(default_pattern_text);
    try std.testing.expectEqual(@as(u4, 2), pattern.get(0, 7));
    try std.testing.expectEqual(@as(u4, 5), pattern.get(3, 4));
    try std.testing.expectEqual(@as(u4, 8), pattern.get(14, 7));
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
    try std.testing.expectError(error.InvalidPatternDigit, parsePatternText(bad_text));
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
    try std.testing.expectError(error.InvalidPatternRowCount, parsePatternText(bad_text));
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
    try std.testing.expectError(error.InvalidPatternColumnCount, parsePatternText(bad_text));
}

test "pattern serialization round trips" {
    const parsed = try parsePatternText(default_pattern_text);
    const serialized = serializePattern(parsed);
    const reparsed = try parsePatternText(&serialized);
    try std.testing.expectEqualDeep(parsed, reparsed);
}

test "grid document contains 225 black shapes" {
    const pattern = try parsePatternText(default_pattern_text);
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

    try std.testing.expectEqual(@as(usize, 225), path_count);
    try std.testing.expect(std.mem.indexOf(u8, svg, "fill='rgb(245,240,230)'") != null);
}

test "default pattern matches the legacy composition svg" {
    const current_pattern = try parsePatternText(default_pattern_text);
    const old_pattern = legacyPattern();

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

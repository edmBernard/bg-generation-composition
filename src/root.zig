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

pub fn buildGridDocument(allocator: std.mem.Allocator) !zsvg.Document {
    const grid_span = (square_size * grid_size) + (gap_size * (grid_size - 1));
    const offset = @divTrunc(canvas_size - grid_span, 2);
    var doc: zsvg.Document = .init(
        allocator,
        canvas_size,
        canvas_size,
        .fromHex(background_hex),
    );
    errdefer doc.deinit();

    // Pattern from Yvaral "Composition en noir"
    const square_type = [grid_size * grid_size]u4{
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

    const fill = zsvg.Fill.solidHex(square_hex);

    for (0..grid_size) |row| {
        for (0..grid_size) |col| {
            const x: f32 = @floatFromInt(offset + (col * (square_size + gap_size)));
            const y: f32 = @floatFromInt(offset + (row * (square_size + gap_size)));
            const extent: f32 = @floatFromInt(square_size);
            const index = row * grid_size + col;
            switch (square_type[index]) {
                // Square
                0 => {
                    const square: [4]zsvg.Point = .{
                        .{ .x = x, .y = y },
                        .{ .x = x + extent, .y = y },
                        .{ .x = x + extent, .y = y + extent },
                        .{ .x = x, .y = y + extent },
                    };
                    try doc.addShape(square, .{ .fill = fill });
                },
                // One triangle missing : right
                1 => {
                    const square: [5]zsvg.Point = .{
                        .{ .x = x, .y = y },
                        .{ .x = x + extent, .y = y },
                        .{ .x = x + extent / 2, .y = y + extent / 2 },
                        .{ .x = x + extent, .y = y + extent },
                        .{ .x = x, .y = y + extent },
                    };
                    try doc.addShape(square, .{ .fill = fill });
                },
                // One triangle missing : bottom
                2 => {
                    const square: [5]zsvg.Point = .{
                        .{ .x = x, .y = y },
                        .{ .x = x + extent, .y = y },
                        .{ .x = x + extent, .y = y + extent },
                        .{ .x = x + extent / 2, .y = y + extent / 2 },
                        .{ .x = x, .y = y + extent },
                    };
                    try doc.addShape(square, .{ .fill = fill });
                },
                // One triangle missing : left
                3 => {
                    const square: [5]zsvg.Point = .{
                        .{ .x = x, .y = y },
                        .{ .x = x + extent, .y = y },
                        .{ .x = x + extent, .y = y + extent },
                        .{ .x = x, .y = y + extent },
                        .{ .x = x + extent / 2, .y = y + extent / 2 },
                    };
                    try doc.addShape(square, .{ .fill = fill });
                },
                // One triangle missing : top
                4 => {
                    const square: [5]zsvg.Point = .{
                        .{ .x = x, .y = y },
                        .{ .x = x + extent / 2, .y = y + extent / 2 },
                        .{ .x = x + extent, .y = y },
                        .{ .x = x + extent, .y = y + extent },
                        .{ .x = x, .y = y + extent },
                    };
                    try doc.addShape(square, .{ .fill = fill });
                },
                // Two triangles missing : right+bottom
                5 => {
                    const square: [3]zsvg.Point = .{
                        .{ .x = x, .y = y },
                        .{ .x = x + extent, .y = y },
                        .{ .x = x, .y = y + extent },
                    };
                    try doc.addShape(square, .{ .fill = fill });
                },
                // Two triangles missing : bottom+left
                6 => {
                    const square: [3]zsvg.Point = .{
                        .{ .x = x, .y = y },
                        .{ .x = x + extent, .y = y },
                        .{ .x = x + extent, .y = y + extent },
                    };
                    try doc.addShape(square, .{ .fill = fill });
                },
                // Two triangles missing : left+top
                7 => {
                    const square: [3]zsvg.Point = .{
                        .{ .x = x + extent, .y = y },
                        .{ .x = x + extent, .y = y + extent },
                        .{ .x = x, .y = y + extent },
                    };
                    try doc.addShape(square, .{ .fill = fill });
                },
                // Two triangles missing : top+right
                8 => {
                    const square: [3]zsvg.Point = .{
                        .{ .x = x, .y = y },
                        .{ .x = x + extent, .y = y + extent },
                        .{ .x = x, .y = y + extent },
                    };
                    try doc.addShape(square, .{ .fill = fill });
                },

                else => {},
            }
        }
    }

    return doc;
}

pub fn writeGridSvg(allocator: std.mem.Allocator, writer: *Io.Writer) !void {
    var doc = try buildGridDocument(allocator);
    defer doc.deinit();
    try doc.writeTo(writer);
}

pub fn saveGridSvg(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !void {
    var doc = try buildGridDocument(allocator);
    defer doc.deinit();
    try doc.save(allocator, io, path);
}

test "grid geometry stays centered" {
    const grid_span = (square_size * grid_size) + (gap_size * (grid_size - 1));
    const offset = @divTrunc(canvas_size - grid_span, 2);
    try std.testing.expectEqual(@as(usize, 1760), grid_span);
    try std.testing.expectEqual(@as(usize, 120), offset);
}

test "grid document contains 225 black squares" {
    var doc = try buildGridDocument(std.testing.allocator);
    defer doc.deinit();

    const svg = try doc.toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(svg);

    var rect_count: usize = 0;
    var search_from: usize = 0;
    while (std.mem.indexOfPos(u8, svg, search_from, "<path")) |index| {
        rect_count += 1;
        search_from = index + 1;
    }

    try std.testing.expect(rect_count == 225);
    try std.testing.expect(std.mem.indexOf(u8, svg, "fill='rgb(245,240,230)'") != null);
}

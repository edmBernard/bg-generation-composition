const std = @import("std");
const Io = std.Io;

const bg_generation_composition = @import("bg_generation_composition");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const io = init.io;
    const output_path = if (args.len >= 2) args[1] else "output.svg";
    try bg_generation_composition.saveGridSvg(arena, io, output_path);

    var stderr_buffer: [512]u8 = undefined;
    var stderr_writer: Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    try stderr_writer.interface.print("Wrote SVG to {s}\n", .{output_path});
    try stderr_writer.interface.flush();
}

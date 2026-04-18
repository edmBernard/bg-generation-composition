const std = @import("std");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

const bg = @import("bg_generation_composition");

const preview_size = 1000.0;
const hud_height = 180.0;
const preview_scale = preview_size / @as(f32, @floatFromInt(bg.canvas_size));
const window_width = @as(c_int, @intFromFloat(preview_size));
const window_height = @as(c_int, @intFromFloat(preview_size + hud_height));

const App = struct {
    io: std.Io,
    pattern_path: []const u8,
    export_path: []const u8,
    pattern: bg.Pattern,
    saved_pattern: bg.Pattern,
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    hovered_cell: ?struct { row: usize, col: usize } = null,
    dirty: bool = false,
    running: bool = true,
    status: [256]u8 = [_]u8{0} ** 256,
    status_len: usize = 0,

    fn setStatus(self: *App, comptime fmt: []const u8, args: anytype) void {
        const msg = std.fmt.bufPrint(&self.status, fmt, args) catch "status overflow";
        self.status_len = msg.len;
    }

    fn updateWindowTitle(self: *App) void {
        var buffer: [128]u8 = undefined;
        const title = std.fmt.bufPrintZ(
            &buffer,
            "Pattern Editor{s} - {s}",
            .{ if (self.dirty) " *" else "", self.pattern_path },
        ) catch return;
        _ = c.SDL_SetWindowTitle(self.window, title.ptr);
    }

    fn setDirty(self: *App, value: bool) void {
        self.dirty = value;
        self.updateWindowTitle();
    }

    fn save(self: *App) void {
        bg.savePattern(self.pattern, self.pattern_path) catch |err| {
            self.setStatus("save failed: {s}", .{@errorName(err)});
            return;
        };
        self.saved_pattern = self.pattern;
        self.setDirty(false);
        self.setStatus("saved {s}", .{self.pattern_path});
    }

    fn exportSvg(self: *App) void {
        bg.saveGridSvgFromPattern(std.heap.smp_allocator, self.io, self.pattern, self.export_path) catch |err| {
            self.setStatus("export failed: {s}", .{@errorName(err)});
            return;
        };
        self.setStatus("exported {s}", .{self.export_path});
    }

    fn reload(self: *App) void {
        const pattern = bg.loadPattern(std.heap.smp_allocator, self.pattern_path) catch |err| {
            self.setStatus("reload failed: {s}", .{@errorName(err)});
            return;
        };
        self.pattern = pattern;
        self.saved_pattern = pattern;
        self.hovered_cell = null;
        self.setDirty(false);
        self.setStatus("reloaded {s}", .{self.pattern_path});
    }

    fn handleMousePosition(self: *App, x: f32, y: f32) void {
        if (y < 0 or y >= preview_size or x < 0 or x >= preview_size) {
            self.hovered_cell = null;
            return;
        }

        const canvas_x = x / preview_scale;
        const canvas_y = y / preview_scale;
        const offset = @as(f32, @floatFromInt((bg.canvas_size - ((bg.square_size * bg.grid_size) + (bg.gap_size * (bg.grid_size - 1)))) / 2));
        const pitch = @as(f32, @floatFromInt(bg.square_size + bg.gap_size));

        if (canvas_x < offset or canvas_y < offset) {
            self.hovered_cell = null;
            return;
        }

        const col_float = (canvas_x - offset) / pitch;
        const row_float = (canvas_y - offset) / pitch;
        const col = @as(usize, @intFromFloat(@floor(col_float)));
        const row = @as(usize, @intFromFloat(@floor(row_float)));
        if (row >= bg.grid_size or col >= bg.grid_size) {
            self.hovered_cell = null;
            return;
        }

        const inner_x = (canvas_x - offset) - (@as(f32, @floatFromInt(col)) * pitch);
        const inner_y = (canvas_y - offset) - (@as(f32, @floatFromInt(row)) * pitch);
        if (inner_x > @as(f32, @floatFromInt(bg.square_size)) or inner_y > @as(f32, @floatFromInt(bg.square_size))) {
            self.hovered_cell = null;
            return;
        }

        self.hovered_cell = .{ .row = row, .col = col };
    }

    fn cycleHovered(self: *App, forward: bool) void {
        const hovered = self.hovered_cell orelse return;
        const old_value = self.pattern.get(hovered.row, hovered.col);
        const old_value_u8: u8 = old_value;
        const new_value: u4 = if (forward)
            @intCast((old_value_u8 + 1) % 9)
        else
            @intCast((old_value_u8 + 8) % 9);
        self.pattern.set(hovered.row, hovered.col, new_value);
        self.setDirty(!std.meta.eql(self.pattern, self.saved_pattern));
        self.setStatus(
            "cell ({d}, {d}) -> tile {d}",
            .{ hovered.row, hovered.col, new_value },
        );
    }

    fn handleEvent(self: *App, event: *c.SDL_Event) void {
        switch (event.type) {
            c.SDL_EVENT_QUIT => self.running = false,
            c.SDL_EVENT_MOUSE_MOTION => self.handleMousePosition(event.motion.x, event.motion.y),
            c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                self.handleMousePosition(event.button.x, event.button.y);
                switch (event.button.button) {
                    c.SDL_BUTTON_LEFT => self.cycleHovered(true),
                    c.SDL_BUTTON_RIGHT => self.cycleHovered(false),
                    else => {},
                }
            },
            c.SDL_EVENT_KEY_DOWN => {
                if (event.key.repeat) return;
                switch (event.key.key) {
                    c.SDLK_Q, c.SDLK_ESCAPE => self.running = false,
                    c.SDLK_S => self.save(),
                    c.SDLK_E => self.exportSvg(),
                    c.SDLK_R => self.reload(),
                    else => {},
                }
            },
            else => {},
        }
    }

    fn render(self: *App) !void {
        try sdlBool(c.SDL_SetRenderDrawColor(self.renderer, 245, 240, 230, 255));
        try sdlBool(c.SDL_RenderClear(self.renderer));

        for (0..bg.grid_size) |row| {
            for (0..bg.grid_size) |col| {
                try renderTile(self.renderer, row, col, self.pattern.get(row, col));
            }
        }

        if (self.hovered_cell) |hovered| {
            try renderHoveredCell(self.renderer, hovered.row, hovered.col);
        }

        try sdlBool(c.SDL_SetRenderDrawColor(self.renderer, 50, 50, 50, 255));
        try sdlBool(c.SDL_RenderLine(self.renderer, 0, preview_size, preview_size, preview_size));

        try renderHud(self);
        try sdlBool(c.SDL_RenderPresent(self.renderer));
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const pattern_path = if (args.len >= 2) args[1] else bg.default_pattern_path;
    const export_path = if (args.len >= 3) args[2] else bg.default_export_path;

    const pattern = try bg.loadPattern(std.heap.smp_allocator, pattern_path);

    try sdlBool(c.SDL_SetAppMetadata("bg_generation_composition_editor", "0.0.1", "com.edmBernard.bg-generation-composition"));
    try sdlBool(c.SDL_Init(c.SDL_INIT_VIDEO));
    defer c.SDL_Quit();

    var window: ?*c.SDL_Window = null;
    var renderer: ?*c.SDL_Renderer = null;
    try sdlBool(c.SDL_CreateWindowAndRenderer(
        "Pattern Editor",
        window_width,
        window_height,
        c.SDL_WINDOW_RESIZABLE,
        &window,
        &renderer,
    ));
    defer c.SDL_DestroyRenderer(renderer.?);
    defer c.SDL_DestroyWindow(window.?);

    var app = App{
        .io = io,
        .pattern_path = pattern_path,
        .export_path = export_path,
        .pattern = pattern,
        .saved_pattern = pattern,
        .window = window.?,
        .renderer = renderer.?,
    };
    app.setStatus("loaded {s}", .{pattern_path});
    app.updateWindowTitle();

    while (app.running) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event)) {
            app.handleEvent(&event);
        }

        try app.render();
        c.SDL_Delay(16);
    }
}

fn renderTile(renderer: *c.SDL_Renderer, row: usize, col: usize, tile: u4) !void {
    const triangles = bg.tileTrianglesForCell(row, col, tile);
    for (0..triangles.len) |triangle_index| {
        try renderTriangle(renderer, triangles.triangles[triangle_index]);
    }
}

fn renderTriangle(renderer: *c.SDL_Renderer, triangle: bg.Triangle) !void {
    var vertices = [3]c.SDL_Vertex{ undefined, undefined, undefined };
    for (0..3) |index| {
        const point = triangle.points[index];
        vertices[index] = .{
            .position = .{
                .x = point.x * preview_scale,
                .y = point.y * preview_scale,
            },
            .color = .{
                .r = 0,
                .g = 0,
                .b = 0,
                .a = 1,
            },
            .tex_coord = .{ .x = 0, .y = 0 },
        };
    }
    try sdlBool(c.SDL_RenderGeometry(renderer, null, &vertices, 3, null, 0));
}

fn renderHoveredCell(renderer: *c.SDL_Renderer, row: usize, col: usize) !void {
    const polygon = bg.tilePolygonForCell(row, col, 0);
    const rect = c.SDL_FRect{
        .x = polygon.points[0].x * preview_scale,
        .y = polygon.points[0].y * preview_scale,
        .w = @as(f32, @floatFromInt(bg.square_size)) * preview_scale,
        .h = @as(f32, @floatFromInt(bg.square_size)) * preview_scale,
    };
    try sdlBool(c.SDL_SetRenderDrawColor(renderer, 200, 70, 30, 255));
    try sdlBool(c.SDL_RenderRect(renderer, &rect));
}

fn renderHud(app: *App) !void {
    try sdlBool(c.SDL_SetRenderDrawColor(app.renderer, 20, 20, 20, 255));

    var line_y: f32 = preview_size + 16.0;
    try renderHudLine(app.renderer, 12, line_y, "Pattern: {s}", .{app.pattern_path});
    line_y += 20;
    try renderHudLine(app.renderer, 12, line_y, "Export:  {s}", .{app.export_path});
    line_y += 20;

    if (app.hovered_cell) |hovered| {
        try renderHudLine(
            app.renderer,
            12,
            line_y,
            "Hover:   row {d} col {d} tile {d}",
            .{ hovered.row, hovered.col, app.pattern.get(hovered.row, hovered.col) },
        );
    } else {
        try renderHudLine(app.renderer, 12, line_y, "Hover:   outside grid", .{});
    }
    line_y += 20;

    try renderHudLine(app.renderer, 12, line_y, "Shortcuts: LMB/RMB cycle  S save  E export  R reload  Q quit", .{});
    line_y += 20;
    try renderHudLine(app.renderer, 12, line_y, "Status: {s}", .{app.status[0..app.status_len]});
}

fn renderHudLine(renderer: *c.SDL_Renderer, x: f32, y: f32, comptime fmt: []const u8, args: anytype) !void {
    var buffer: [256]u8 = undefined;
    const text = try std.fmt.bufPrintZ(&buffer, fmt, args);
    try sdlBool(c.SDL_RenderDebugText(renderer, x, y, text.ptr));
}

fn sdlBool(ok: bool) !void {
    if (!ok) return error.SdlFailure;
}

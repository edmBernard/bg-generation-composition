const std = @import("std");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

const bg = @import("bg_generation_composition");

// Layout constants
const sidebar_width: f32 = 260.0;
const status_height: f32 = 26.0;
const min_grid_size = 1;
const max_grid_size = 60;
const min_zoom = 0.25;
const max_zoom = 20.0;
const window_width = 1200;
const window_height = 900;

// SDL_RenderDebugText draws an 8x8 monospace bitmap font.
const glyph_w: f32 = 8.0;
const glyph_h: f32 = 8.0;

// Theme
const col_bg = [4]u8{ 245, 240, 230, 255 };
const col_panel = [4]u8{ 38, 42, 50, 255 };
const col_panel_alt = [4]u8{ 48, 53, 62, 255 };
const col_divider = [4]u8{ 70, 76, 86, 255 };
const col_text = [4]u8{ 230, 230, 230, 255 };
const col_text_dim = [4]u8{ 160, 168, 180, 255 };
const col_text_accent = [4]u8{ 255, 200, 90, 255 };
const col_btn = [4]u8{ 70, 78, 92, 255 };
const col_btn_hover = [4]u8{ 95, 110, 130, 255 };
const col_btn_border = [4]u8{ 110, 122, 140, 255 };
const col_btn_action = [4]u8{ 60, 110, 90, 255 };
const col_btn_action_hover = [4]u8{ 80, 140, 115, 255 };
const col_separator = [4]u8{ 30, 30, 30, 255 };
const col_status_bg = [4]u8{ 28, 32, 38, 255 };
const col_hover_outline = [4]u8{ 220, 80, 50, 255 };
const col_dirty = [4]u8{ 255, 130, 80, 255 };
const col_clean = [4]u8{ 120, 200, 140, 255 };

const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    fn contains(self: Rect, px: f32, py: f32) bool {
        return px >= self.x and px <= self.x + self.w and py >= self.y and py <= self.y + self.h;
    }

    fn centerX(self: Rect) f32 {
        return self.x + (self.w / 2.0);
    }

    fn centerY(self: Rect) f32 {
        return self.y + (self.h / 2.0);
    }

    fn toFRect(self: Rect) c.SDL_FRect {
        return .{ .x = self.x, .y = self.y, .w = self.w, .h = self.h };
    }
};

const ButtonId = enum {
    grid_minus,
    grid_plus,
    zoom_minus,
    zoom_plus,
    fit,
    reset,
    save,
    export_svg,
    reload,
};

const ButtonStyle = enum { normal, action };

const Button = struct {
    id: ButtonId,
    rect: Rect,
    label: []const u8,
    style: ButtonStyle = .normal,
};

/// Layout of all sidebar controls. Coordinates are stored relative to the
/// sidebar's top-left for easier resizing-time recalculation.
const SidebarLayout = struct {
    section_grid_y: f32,
    section_view_y: f32,
    section_actions_y: f32,
    section_info_y: f32,
    section_help_y: f32,
    grid_value_rect: Rect,
    zoom_value_rect: Rect,
    buttons: [9]Button,
};

const App = struct {
    allocator: std.mem.Allocator,
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
    zoom: f32 = 1.0,
    pan_x: f32 = 0.0,
    pan_y: f32 = 0.0,
    mouse_x: f32 = 0.0,
    mouse_y: f32 = 0.0,
    dragging: bool = false,
    drag_button: u8 = 0,
    drag_last_x: f32 = 0.0,
    drag_last_y: f32 = 0.0,
    space_down: bool = false,

    fn deinit(self: *App) void {
        self.pattern.deinit();
        self.saved_pattern.deinit();
    }

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

    fn refreshDirty(self: *App) void {
        self.setDirty(!self.pattern.eql(self.saved_pattern));
    }

    fn save(self: *App) void {
        bg.savePattern(self.pattern, self.pattern_path) catch |err| {
            self.setStatus("save failed: {s}", .{@errorName(err)});
            return;
        };

        self.saved_pattern.deinit();
        self.saved_pattern = self.pattern.clone(self.allocator) catch |err| {
            self.setStatus("save copy failed: {s}", .{@errorName(err)});
            return;
        };
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
        var pattern = bg.loadPattern(self.allocator, self.pattern_path) catch |err| {
            self.setStatus("reload failed: {s}", .{@errorName(err)});
            return;
        };
        errdefer pattern.deinit();

        const saved = pattern.clone(self.allocator) catch |err| {
            self.setStatus("reload clone failed: {s}", .{@errorName(err)});
            return;
        };

        self.pattern.deinit();
        self.saved_pattern.deinit();
        self.pattern = pattern;
        self.saved_pattern = saved;
        self.hovered_cell = null;
        self.fitView();
        self.setDirty(false);
        self.setStatus("reloaded {s}", .{self.pattern_path});
    }

    fn fitView(self: *App) void {
        self.zoom = 1.0;
        self.pan_x = 0.0;
        self.pan_y = 0.0;
    }

    fn resetView(self: *App) void {
        self.fitView();
        self.setStatus("view reset", .{});
    }

    fn windowSize(self: *App) struct { w: f32, h: f32 } {
        var width: c_int = 0;
        var height: c_int = 0;
        _ = c.SDL_GetWindowSize(self.window, &width, &height);
        return .{ .w = @floatFromInt(width), .h = @floatFromInt(height) };
    }

    fn previewRect(self: *App) Rect {
        const size = self.windowSize();
        const w = @max(120.0, size.w - sidebar_width);
        const h = @max(120.0, size.h - status_height);
        return .{ .x = 0.0, .y = 0.0, .w = w, .h = h };
    }

    fn sidebarRect(self: *App) Rect {
        const size = self.windowSize();
        const h = @max(120.0, size.h - status_height);
        return .{ .x = size.w - sidebar_width, .y = 0.0, .w = sidebar_width, .h = h };
    }

    fn statusRect(self: *App) Rect {
        const size = self.windowSize();
        return .{ .x = 0.0, .y = size.h - status_height, .w = size.w, .h = status_height };
    }

    fn viewScale(self: *App, preview: Rect) f32 {
        const canvas_extent = @as(f32, @floatFromInt(bg.canvas_size));
        return @min(preview.w / canvas_extent, preview.h / canvas_extent) * self.zoom;
    }

    fn clampPan(self: *App, preview: Rect) void {
        const canvas_extent = @as(f32, @floatFromInt(bg.canvas_size));
        const scaled_extent = canvas_extent * self.viewScale(preview);
        const max_x = @max(0.0, (scaled_extent - preview.w) / 2.0);
        const max_y = @max(0.0, (scaled_extent - preview.h) / 2.0);
        self.pan_x = std.math.clamp(self.pan_x, -max_x, max_x);
        self.pan_y = std.math.clamp(self.pan_y, -max_y, max_y);
    }

    fn canvasToScreen(self: *App, preview: Rect, point: bg.Point) bg.Point {
        const canvas_center = @as(f32, @floatFromInt(bg.canvas_size)) / 2.0;
        const scale = self.viewScale(preview);
        return .{
            .x = preview.centerX() + ((point.x - canvas_center) * scale) + self.pan_x,
            .y = preview.centerY() + ((point.y - canvas_center) * scale) + self.pan_y,
        };
    }

    fn screenToCanvas(self: *App, preview: Rect, x: f32, y: f32) ?bg.Point {
        if (!preview.contains(x, y)) return null;

        const canvas_center = @as(f32, @floatFromInt(bg.canvas_size)) / 2.0;
        const scale = self.viewScale(preview);
        const world_x = canvas_center + ((x - preview.centerX() - self.pan_x) / scale);
        const world_y = canvas_center + ((y - preview.centerY() - self.pan_y) / scale);

        if (world_x < 0.0 or world_x >= @as(f32, @floatFromInt(bg.canvas_size))) return null;
        if (world_y < 0.0 or world_y >= @as(f32, @floatFromInt(bg.canvas_size))) return null;

        return .{ .x = world_x, .y = world_y };
    }

    fn updateHoveredFromMouse(self: *App, x: f32, y: f32) void {
        const preview = self.previewRect();
        self.clampPan(preview);

        const canvas_point = self.screenToCanvas(preview, x, y) orelse {
            self.hovered_cell = null;
            return;
        };

        const layout = bg.gridLayout(self.pattern.size);
        if (canvas_point.x < layout.offset or canvas_point.y < layout.offset) {
            self.hovered_cell = null;
            return;
        }

        const col_float = (canvas_point.x - layout.offset) / layout.pitch;
        const row_float = (canvas_point.y - layout.offset) / layout.pitch;
        const col = @as(usize, @intFromFloat(@floor(col_float)));
        const row = @as(usize, @intFromFloat(@floor(row_float)));
        if (row >= self.pattern.size or col >= self.pattern.size) {
            self.hovered_cell = null;
            return;
        }

        const inner_x = (canvas_point.x - layout.offset) - (@as(f32, @floatFromInt(col)) * layout.pitch);
        const inner_y = (canvas_point.y - layout.offset) - (@as(f32, @floatFromInt(row)) * layout.pitch);
        if (inner_x > layout.square_extent or inner_y > layout.square_extent) {
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
        self.refreshDirty();
        self.setStatus(
            "cell ({d}, {d}) -> tile {d}",
            .{ hovered.row, hovered.col, new_value },
        );
    }

    fn movePanBy(self: *App, dx: f32, dy: f32) void {
        const preview = self.previewRect();
        self.pan_x += dx;
        self.pan_y += dy;
        self.clampPan(preview);
    }

    fn setZoomAround(self: *App, target_zoom: f32, focus_x: f32, focus_y: f32) void {
        const preview = self.previewRect();
        const focus_canvas = self.screenToCanvas(preview, focus_x, focus_y);
        self.zoom = std.math.clamp(target_zoom, min_zoom, max_zoom);

        if (focus_canvas) |canvas_point| {
            const scale = self.viewScale(preview);
            const canvas_center = @as(f32, @floatFromInt(bg.canvas_size)) / 2.0;
            self.pan_x = focus_x - preview.centerX() - ((canvas_point.x - canvas_center) * scale);
            self.pan_y = focus_y - preview.centerY() - ((canvas_point.y - canvas_center) * scale);
        }

        self.clampPan(preview);
        self.updateHoveredFromMouse(self.mouse_x, self.mouse_y);
    }

    fn zoomByFactor(self: *App, factor: f32, focus_x: f32, focus_y: f32) void {
        self.setZoomAround(self.zoom * factor, focus_x, focus_y);
        self.setStatus("zoom {d:.0}%", .{self.zoom * 100.0});
    }

    fn resizePattern(self: *App, new_size: usize) void {
        const clamped_size = std.math.clamp(new_size, min_grid_size, max_grid_size);
        if (clamped_size == self.pattern.size) return;

        const resized = self.pattern.resized(self.allocator, clamped_size) catch |err| {
            self.setStatus("resize failed: {s}", .{@errorName(err)});
            return;
        };

        self.pattern.deinit();
        self.pattern = resized;
        self.hovered_cell = null;
        self.fitView();
        self.refreshDirty();
        self.setStatus("grid size -> {d}", .{clamped_size});
    }

    fn startDrag(self: *App, button: u8, x: f32, y: f32) void {
        self.dragging = true;
        self.drag_button = button;
        self.drag_last_x = x;
        self.drag_last_y = y;
    }

    fn stopDrag(self: *App, button: u8) void {
        if (self.dragging and self.drag_button == button) {
            self.dragging = false;
            self.drag_button = 0;
        }
    }

    fn computeLayout(self: *App) SidebarLayout {
        const sidebar = self.sidebarRect();
        const pad: f32 = 14.0;
        const section_gap: f32 = 18.0;
        const header_h: f32 = 24.0;
        const row_h: f32 = 30.0;
        const btn_size: f32 = 30.0;
        const inner_x = sidebar.x + pad;
        const inner_w = sidebar.w - pad * 2.0;

        var y: f32 = pad;

        // Grid section
        const section_grid_y = y;
        y += header_h;
        const grid_row_y = y;
        const grid_minus = Button{
            .id = .grid_minus,
            .rect = .{ .x = inner_x, .y = grid_row_y, .w = btn_size, .h = btn_size },
            .label = "-",
        };
        const grid_plus = Button{
            .id = .grid_plus,
            .rect = .{ .x = inner_x + inner_w - btn_size, .y = grid_row_y, .w = btn_size, .h = btn_size },
            .label = "+",
        };
        const grid_value_rect = Rect{
            .x = grid_minus.rect.x + grid_minus.rect.w,
            .y = grid_row_y,
            .w = inner_w - btn_size * 2.0,
            .h = btn_size,
        };
        y += row_h + section_gap;

        // View section
        const section_view_y = y;
        y += header_h;
        const zoom_row_y = y;
        const zoom_minus = Button{
            .id = .zoom_minus,
            .rect = .{ .x = inner_x, .y = zoom_row_y, .w = btn_size, .h = btn_size },
            .label = "-",
        };
        const zoom_plus = Button{
            .id = .zoom_plus,
            .rect = .{ .x = inner_x + inner_w - btn_size, .y = zoom_row_y, .w = btn_size, .h = btn_size },
            .label = "+",
        };
        const zoom_value_rect = Rect{
            .x = zoom_minus.rect.x + zoom_minus.rect.w,
            .y = zoom_row_y,
            .w = inner_w - btn_size * 2.0,
            .h = btn_size,
        };
        y += row_h + 6.0;

        const fit_w = (inner_w - 8.0) / 2.0;
        const fit = Button{
            .id = .fit,
            .rect = .{ .x = inner_x, .y = y, .w = fit_w, .h = btn_size },
            .label = "Fit",
        };
        const reset = Button{
            .id = .reset,
            .rect = .{ .x = inner_x + fit_w + 8.0, .y = y, .w = fit_w, .h = btn_size },
            .label = "Reset",
        };
        y += row_h + section_gap;

        // Actions section
        const section_actions_y = y;
        y += header_h;
        const save_btn = Button{
            .id = .save,
            .rect = .{ .x = inner_x, .y = y, .w = inner_w, .h = btn_size },
            .label = "Save  (S)",
            .style = .action,
        };
        y += btn_size + 6.0;
        const export_btn = Button{
            .id = .export_svg,
            .rect = .{ .x = inner_x, .y = y, .w = inner_w, .h = btn_size },
            .label = "Export SVG  (E)",
            .style = .action,
        };
        y += btn_size + 6.0;
        const reload_btn = Button{
            .id = .reload,
            .rect = .{ .x = inner_x, .y = y, .w = inner_w, .h = btn_size },
            .label = "Reload  (R)",
        };
        y += btn_size + section_gap;

        // Info section
        const section_info_y = y;
        y += header_h + 16.0 * 4.0;

        // Help section
        const section_help_y = y;

        return .{
            .section_grid_y = section_grid_y,
            .section_view_y = section_view_y,
            .section_actions_y = section_actions_y,
            .section_info_y = section_info_y,
            .section_help_y = section_help_y,
            .grid_value_rect = grid_value_rect,
            .zoom_value_rect = zoom_value_rect,
            .buttons = .{
                grid_minus, grid_plus,
                zoom_minus, zoom_plus,
                fit,        reset,
                save_btn,   export_btn,
                reload_btn,
            },
        };
    }

    fn buttonAt(self: *App, x: f32, y: f32) ?ButtonId {
        const layout = self.computeLayout();
        for (layout.buttons) |button| {
            if (button.rect.contains(x, y)) return button.id;
        }
        return null;
    }

    fn triggerButton(self: *App, button_id: ButtonId) void {
        switch (button_id) {
            .grid_minus => self.resizePattern(self.pattern.size -| 1),
            .grid_plus => self.resizePattern(self.pattern.size + 1),
            .zoom_minus => self.zoomByFactor(1.0 / 1.2, self.previewRect().centerX(), self.previewRect().centerY()),
            .zoom_plus => self.zoomByFactor(1.2, self.previewRect().centerX(), self.previewRect().centerY()),
            .fit => {
                self.fitView();
                self.setStatus("fit to view", .{});
            },
            .reset => self.resetView(),
            .save => self.save(),
            .export_svg => self.exportSvg(),
            .reload => self.reload(),
        }
    }

    fn handleMouseMotion(self: *App, x: f32, y: f32) void {
        self.mouse_x = x;
        self.mouse_y = y;

        if (self.dragging) {
            self.movePanBy(x - self.drag_last_x, y - self.drag_last_y);
            self.drag_last_x = x;
            self.drag_last_y = y;
        }

        self.updateHoveredFromMouse(x, y);
    }

    fn handleMouseButtonDown(self: *App, button: u8, x: f32, y: f32) void {
        self.mouse_x = x;
        self.mouse_y = y;

        if (button == c.SDL_BUTTON_LEFT) {
            if (self.buttonAt(x, y)) |button_id| {
                self.triggerButton(button_id);
                return;
            }

            const preview = self.previewRect();
            if (preview.contains(x, y) and self.space_down) {
                self.startDrag(button, x, y);
                return;
            }
        }

        if (button == c.SDL_BUTTON_MIDDLE) {
            if (self.previewRect().contains(x, y)) {
                self.startDrag(button, x, y);
            }
            return;
        }

        self.updateHoveredFromMouse(x, y);
        switch (button) {
            c.SDL_BUTTON_LEFT => self.cycleHovered(true),
            c.SDL_BUTTON_RIGHT => self.cycleHovered(false),
            else => {},
        }
    }

    fn handleWheel(self: *App, event: *c.SDL_Event) void {
        const preview = self.previewRect();
        const mouse_x = event.wheel.mouse_x;
        const mouse_y = event.wheel.mouse_y;
        if (!preview.contains(mouse_x, mouse_y)) return;

        if (event.wheel.y > 0) {
            self.zoomByFactor(std.math.pow(f32, 1.2, event.wheel.y), mouse_x, mouse_y);
        } else if (event.wheel.y < 0) {
            self.zoomByFactor(std.math.pow(f32, 1.0 / 1.2, -event.wheel.y), mouse_x, mouse_y);
        }
    }

    fn handleEvent(self: *App, event: *c.SDL_Event) void {
        switch (event.type) {
            c.SDL_EVENT_QUIT => self.running = false,
            c.SDL_EVENT_MOUSE_MOTION => self.handleMouseMotion(event.motion.x, event.motion.y),
            c.SDL_EVENT_MOUSE_BUTTON_DOWN => self.handleMouseButtonDown(event.button.button, event.button.x, event.button.y),
            c.SDL_EVENT_MOUSE_BUTTON_UP => self.stopDrag(event.button.button),
            c.SDL_EVENT_MOUSE_WHEEL => self.handleWheel(event),
            c.SDL_EVENT_KEY_DOWN => {
                if (event.key.repeat) return;
                switch (event.key.key) {
                    c.SDLK_Q, c.SDLK_ESCAPE => self.running = false,
                    c.SDLK_S => self.save(),
                    c.SDLK_E => self.exportSvg(),
                    c.SDLK_R => self.reload(),
                    c.SDLK_EQUALS, c.SDLK_KP_PLUS => self.zoomByFactor(1.2, self.previewRect().centerX(), self.previewRect().centerY()),
                    c.SDLK_MINUS, c.SDLK_KP_MINUS => self.zoomByFactor(1.0 / 1.2, self.previewRect().centerX(), self.previewRect().centerY()),
                    c.SDLK_0 => {
                        self.fitView();
                        self.setStatus("fit to view", .{});
                    },
                    c.SDLK_LEFT => self.movePanBy(40.0, 0.0),
                    c.SDLK_RIGHT => self.movePanBy(-40.0, 0.0),
                    c.SDLK_UP => self.movePanBy(0.0, 40.0),
                    c.SDLK_DOWN => self.movePanBy(0.0, -40.0),
                    c.SDLK_SPACE => self.space_down = true,
                    else => {},
                }
            },
            c.SDL_EVENT_KEY_UP => {
                if (event.key.key == c.SDLK_SPACE) {
                    self.space_down = false;
                }
            },
            else => {},
        }
    }

    fn render(self: *App) !void {
        const preview = self.previewRect();
        self.clampPan(preview);

        try setColor(self.renderer, col_bg);
        try sdlBool(c.SDL_RenderClear(self.renderer));

        // Clip preview drawing so it cannot bleed under the sidebar.
        const clip = c.SDL_Rect{
            .x = 0,
            .y = 0,
            .w = @intFromFloat(preview.w),
            .h = @intFromFloat(preview.h),
        };
        try sdlBool(c.SDL_SetRenderClipRect(self.renderer, &clip));

        for (0..self.pattern.size) |row| {
            for (0..self.pattern.size) |col| {
                try renderTile(self, preview, row, col, self.pattern.get(row, col));
            }
        }

        if (self.hovered_cell) |hovered| {
            try renderHoveredCell(self, preview, hovered.row, hovered.col);
        }

        try sdlBool(c.SDL_SetRenderClipRect(self.renderer, null));

        try renderSidebar(self);
        try renderStatusBar(self);

        try sdlBool(c.SDL_RenderPresent(self.renderer));
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const pattern_path = if (args.len >= 2) args[1] else bg.default_pattern_path;
    const export_path = if (args.len >= 3) args[2] else bg.default_export_path;

    var pattern = try bg.loadPattern(std.heap.smp_allocator, pattern_path);
    errdefer pattern.deinit();
    var saved_pattern = try pattern.clone(std.heap.smp_allocator);
    errdefer saved_pattern.deinit();

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
        .allocator = std.heap.smp_allocator,
        .io = io,
        .pattern_path = pattern_path,
        .export_path = export_path,
        .pattern = pattern,
        .saved_pattern = saved_pattern,
        .window = window.?,
        .renderer = renderer.?,
    };
    defer app.deinit();
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

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

fn renderTile(app: *App, preview: Rect, row: usize, col: usize, tile: u4) !void {
    const triangles = bg.tileTrianglesForCell(row, col, app.pattern.size, tile);
    for (0..triangles.len) |triangle_index| {
        try renderTriangle(app, preview, triangles.triangles[triangle_index]);
    }
}

fn renderTriangle(app: *App, preview: Rect, triangle: bg.Triangle) !void {
    var vertices = [3]c.SDL_Vertex{ undefined, undefined, undefined };
    for (0..3) |index| {
        const point = app.canvasToScreen(preview, triangle.points[index]);
        vertices[index] = .{
            .position = .{ .x = point.x, .y = point.y },
            .color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            .tex_coord = .{ .x = 0, .y = 0 },
        };
    }
    try sdlBool(c.SDL_RenderGeometry(app.renderer, null, &vertices, 3, null, 0));
}

fn renderHoveredCell(app: *App, preview: Rect, row: usize, col: usize) !void {
    const polygon = bg.tilePolygonForCell(row, col, app.pattern.size, 0);
    const top_left = app.canvasToScreen(preview, polygon.points[0]);
    const scale = app.viewScale(preview);
    const layout = bg.gridLayout(app.pattern.size);
    const rect = c.SDL_FRect{
        .x = top_left.x,
        .y = top_left.y,
        .w = layout.square_extent * scale,
        .h = layout.square_extent * scale,
    };
    try setColor(app.renderer, col_hover_outline);
    try sdlBool(c.SDL_RenderRect(app.renderer, &rect));
}

fn renderSidebar(app: *App) !void {
    const sidebar = app.sidebarRect();
    const layout = app.computeLayout();
    const hovered_button = app.buttonAt(app.mouse_x, app.mouse_y);

    // Sidebar background
    try setColor(app.renderer, col_panel);
    try sdlBool(c.SDL_RenderFillRect(app.renderer, &sidebar.toFRect()));

    // Vertical separator between preview and sidebar
    try setColor(app.renderer, col_separator);
    try sdlBool(c.SDL_RenderLine(app.renderer, sidebar.x, sidebar.y, sidebar.x, sidebar.y + sidebar.h));

    const inner_x = sidebar.x + 14.0;
    const inner_w = sidebar.w - 28.0;

    // Section headers
    try renderSectionHeader(app.renderer, inner_x, layout.section_grid_y, inner_w, "GRID SIZE");
    try renderSectionHeader(app.renderer, inner_x, layout.section_view_y, inner_w, "VIEW");
    try renderSectionHeader(app.renderer, inner_x, layout.section_actions_y, inner_w, "ACTIONS");
    try renderSectionHeader(app.renderer, inner_x, layout.section_info_y, inner_w, "INFO");
    try renderSectionHeader(app.renderer, inner_x, layout.section_help_y, inner_w, "SHORTCUTS");

    // Buttons
    for (layout.buttons) |button| {
        const active = hovered_button != null and hovered_button.? == button.id;
        try renderButton(app.renderer, button.rect, button.label, button.style, active);
    }

    // Inline value pills between -/+ buttons
    {
        var buf: [32]u8 = undefined;
        const text = try std.fmt.bufPrintZ(&buf, "{d} x {d}", .{ app.pattern.size, app.pattern.size });
        try renderValuePill(app.renderer, layout.grid_value_rect, text);
    }
    {
        var buf: [32]u8 = undefined;
        const text = try std.fmt.bufPrintZ(&buf, "{d:.0}%", .{app.zoom * 100.0});
        try renderValuePill(app.renderer, layout.zoom_value_rect, text);
    }

    // Info section content
    {
        const label_w: f32 = 56.0;
        const line_h: f32 = 16.0;
        var info_y = layout.section_info_y + 24.0;

        try drawText(app.renderer, inner_x, info_y, "Pattern", col_text_dim);
        try drawTextEllipsis(app.renderer, inner_x + label_w, info_y, inner_w - label_w, app.pattern_path, col_text);
        info_y += line_h;

        try drawText(app.renderer, inner_x, info_y, "Export", col_text_dim);
        try drawTextEllipsis(app.renderer, inner_x + label_w, info_y, inner_w - label_w, app.export_path, col_text);
        info_y += line_h;

        try drawText(app.renderer, inner_x, info_y, "Hover", col_text_dim);
        if (app.hovered_cell) |h| {
            var hbuf: [64]u8 = undefined;
            const text = try std.fmt.bufPrintZ(&hbuf, "r {d}, c {d}, tile {d}", .{ h.row, h.col, app.pattern.get(h.row, h.col) });
            try drawText(app.renderer, inner_x + label_w, info_y, std.mem.span(text.ptr), col_text_accent);
        } else {
            try drawText(app.renderer, inner_x + label_w, info_y, "-", col_text_dim);
        }
        info_y += line_h;

        try drawText(app.renderer, inner_x, info_y, "State", col_text_dim);
        if (app.dirty) {
            try drawText(app.renderer, inner_x + label_w, info_y, "modified", col_dirty);
        } else {
            try drawText(app.renderer, inner_x + label_w, info_y, "saved", col_clean);
        }
    }

    // Help section content
    {
        const help_lines = [_][]const u8{
            "LMB / RMB    cycle tile",
            "Wheel        zoom",
            "+ / -        zoom",
            "0            fit",
            "Arrows       pan",
            "MMB / Space  drag pan",
            "S            save",
            "E            export",
            "R            reload",
            "Q / Esc      quit",
        };
        var help_y = layout.section_help_y + 24.0;
        const line_h: f32 = 14.0;
        for (help_lines) |line| {
            try drawText(app.renderer, inner_x, help_y, line, col_text_dim);
            help_y += line_h;
        }
    }
}

fn renderValuePill(renderer: *c.SDL_Renderer, rect: Rect, text: [:0]const u8) !void {
    try setColor(renderer, col_panel_alt);
    try sdlBool(c.SDL_RenderFillRect(renderer, &rect.toFRect()));
    try setColor(renderer, col_btn_border);
    try sdlBool(c.SDL_RenderRect(renderer, &rect.toFRect()));
    try drawCenteredText(renderer, rect, text, col_text);
}

fn renderSectionHeader(renderer: *c.SDL_Renderer, x: f32, y: f32, w: f32, text: []const u8) !void {
    try drawText(renderer, x, y + 4.0, text, col_text_accent);
    const ly = y + 18.0;
    try setColor(renderer, col_divider);
    try sdlBool(c.SDL_RenderLine(renderer, x, ly, x + w, ly));
}

fn renderButton(renderer: *c.SDL_Renderer, rect: Rect, label: []const u8, style: ButtonStyle, hover: bool) !void {
    const fill = switch (style) {
        .normal => if (hover) col_btn_hover else col_btn,
        .action => if (hover) col_btn_action_hover else col_btn_action,
    };
    try setColor(renderer, fill);
    try sdlBool(c.SDL_RenderFillRect(renderer, &rect.toFRect()));
    try setColor(renderer, col_btn_border);
    try sdlBool(c.SDL_RenderRect(renderer, &rect.toFRect()));

    var buf: [64]u8 = undefined;
    const len = @min(label.len, buf.len - 1);
    @memcpy(buf[0..len], label[0..len]);
    buf[len] = 0;
    const tw = @as(f32, @floatFromInt(len)) * glyph_w;
    const tx = rect.x + (rect.w - tw) / 2.0;
    const ty = rect.y + (rect.h - glyph_h) / 2.0;
    try setColor(renderer, col_text);
    try sdlBool(c.SDL_RenderDebugText(renderer, tx, ty, &buf[0]));
}

fn renderStatusBar(app: *App) !void {
    const bar = app.statusRect();
    try setColor(app.renderer, col_status_bg);
    try sdlBool(c.SDL_RenderFillRect(app.renderer, &bar.toFRect()));
    try setColor(app.renderer, col_separator);
    try sdlBool(c.SDL_RenderLine(app.renderer, bar.x, bar.y, bar.x + bar.w, bar.y));

    const text_y = bar.y + (bar.h - glyph_h) / 2.0;
    try drawText(app.renderer, 12.0, text_y, app.status[0..app.status_len], col_text);

    var buf: [128]u8 = undefined;
    const right = try std.fmt.bufPrintZ(
        &buf,
        "Grid {d}x{d}   Zoom {d:.0}%   Pan ({d:.0}, {d:.0}){s}",
        .{
            app.pattern.size, app.pattern.size,
            app.zoom * 100.0, app.pan_x,
            app.pan_y,        if (app.dirty) "   *" else "",
        },
    );
    const text_slice = std.mem.span(right.ptr);
    const text_w = @as(f32, @floatFromInt(text_slice.len)) * glyph_w;
    const right_x = bar.x + bar.w - text_w - 12.0;
    try drawText(app.renderer, right_x, text_y, text_slice, if (app.dirty) col_dirty else col_text_dim);
}

// ---------------------------------------------------------------------------
// Text + drawing utilities
// ---------------------------------------------------------------------------

fn drawText(renderer: *c.SDL_Renderer, x: f32, y: f32, text: []const u8, color: [4]u8) !void {
    var buf: [512]u8 = undefined;
    const len = @min(text.len, buf.len - 1);
    @memcpy(buf[0..len], text[0..len]);
    buf[len] = 0;
    try setColor(renderer, color);
    try sdlBool(c.SDL_RenderDebugText(renderer, x, y, &buf[0]));
}

fn drawCenteredText(renderer: *c.SDL_Renderer, rect: Rect, text: [:0]const u8, color: [4]u8) !void {
    const tw = @as(f32, @floatFromInt(text.len)) * glyph_w;
    const tx = rect.x + (rect.w - tw) / 2.0;
    const ty = rect.y + (rect.h - glyph_h) / 2.0;
    try setColor(renderer, color);
    try sdlBool(c.SDL_RenderDebugText(renderer, tx, ty, text.ptr));
}

fn drawTextEllipsis(renderer: *c.SDL_Renderer, x: f32, y: f32, max_w: f32, text: []const u8, color: [4]u8) !void {
    const max_chars: usize = @intFromFloat(@max(1.0, @floor(max_w / glyph_w)));
    if (text.len <= max_chars) {
        try drawText(renderer, x, y, text, color);
        return;
    }
    if (max_chars <= 3) {
        try drawText(renderer, x, y, text[0..max_chars], color);
        return;
    }
    var buf: [512]u8 = undefined;
    const keep = max_chars - 3;
    const tail_len = @min(keep, text.len);
    const start = text.len - tail_len;
    buf[0] = '.';
    buf[1] = '.';
    buf[2] = '.';
    @memcpy(buf[3 .. 3 + tail_len], text[start..]);
    try drawText(renderer, x, y, buf[0 .. 3 + tail_len], color);
}

fn setColor(renderer: *c.SDL_Renderer, color: [4]u8) !void {
    try sdlBool(c.SDL_SetRenderDrawColor(renderer, color[0], color[1], color[2], color[3]));
}

fn sdlBool(ok: bool) !void {
    if (!ok) return error.SdlFailure;
}

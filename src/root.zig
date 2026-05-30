const std = @import("std");
const c = @import("c");

const DragonGenerator = struct {
    path: std.ArrayList(Direction) = .empty,

    pub fn deinit(self: *DragonGenerator, alloc: std.mem.Allocator) void {
        self.path.deinit(alloc);
    }

    pub fn genNext(self: *DragonGenerator, alloc: std.mem.Allocator) !void {
        if (self.path.items.len == 0) {
            try self.path.append(alloc, .right);
            return;
        }

        var new = try self.path.addManyAt(alloc, 0, self.path.items.len);
        const old = self.path.items[new.len..];
        for (new[0..], 0..) |*n, i| n.* = old[new.len - i - 1].rotCW90().invert();
    }

    pub fn format(self: DragonGenerator, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        for (self.path.items) |d| {
            try writer.print("{f} ", .{d});
        }
    }

    const Direction = enum {
        up,
        right,
        down,
        left,

        fn rotCW90(self: Direction) Direction {
            return switch (self) {
                .up => .right,
                .right => .down,
                .down => .left,
                .left => .up,
            };
        }

        fn invert(self: Direction) Direction {
            return switch (self) {
                .up => .down,
                .right => .left,
                .down => .up,
                .left => .right,
            };
        }

        pub fn format(self: Direction, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.print("{s}", .{switch (self) {
                .up => "↑",
                .right => "→",
                .down => "↓",
                .left => "←",
            }});
        }
    };
};

const HSV = struct { h: f32, s: f32, v: f32 };
const RGB = struct { r: f32, g: f32, b: f32 };

pub fn rgb2hsv(rgb: RGB) HSV {
    const r = rgb.r;
    const g = rgb.g;
    const b = rgb.b;

    const cmax = @max(r, @max(g, b));
    const cmin = @min(r, @min(g, b));
    const delta = cmax - cmin;

    const v = cmax;

    const s = if (cmax == 0) 0 else delta / cmax;

    const h = blk: {
        if (delta == 0) break :blk 0;

        const raw =
            if (cmax == r)
                60 * @mod((g - b) / delta, 6)
            else if (cmax == g)
                60 * (b - r) / delta + 2
            else
                60 * (r - g) / delta + 4;

        break :blk if (raw < 0) raw + 360 else raw;
    };

    return .{ .h = h, .s = s, .v = v };
}

pub fn hsv2rgb(hsv: HSV) RGB {
    const h = hsv.h;
    const s = hsv.s;
    const v = hsv.v;

    if (s == 0) return .{ .r = v, .g = v, .b = v };

    const sector = h / 60;
    const i: u32 = @intFromFloat(sector);
    const f = sector - @as(f32, @floatFromInt(i));
    const p = v * (1 - s);
    const q = v * (1 - s * f);
    const t = v * (1 - s * (1 - f));

    return switch (i % 6) {
        0 => .{ .r = v, .g = t, .b = p },
        1 => .{ .r = q, .g = v, .b = p },
        2 => .{ .r = p, .g = v, .b = t },
        3 => .{ .r = p, .g = q, .b = v },
        4 => .{ .r = t, .g = p, .b = v },
        5 => .{ .r = v, .g = p, .b = q },
        else => unreachable,
    };
}

const DragonVecBatch = struct {
    const vec_len = 64;
    const VecType = @Vector(vec_len, u4);
    batches: std.ArrayList(VecType),

    const Direction = enum(u4) {
        empty,
        up,
        right,
        left,
        down,
    };

    pub fn init(gpa: std.mem.Allocator) !DragonVecBatch {
        var vec: VecType = @splat(0);
        vec[0] = @intFromEnum(Direction.up);

        var ret = DragonVecBatch{ .batches = .empty };
        try ret.batches.append(gpa, vec);

        return ret;
    }

    pub fn deinit(self: *DragonVecBatch, gpa: std.mem.Allocator) void {
        self.batches.deinit(gpa);
    }

    const Len = enum(u8) {
        @"1" = 1,
        @"2" = 2,
        @"4" = 4,
        @"8" = 8,
        @"16" = 16,
        @"32" = 32,
    };

    pub fn a(vec: VecType, comptime len: Len) VecType {
        const l = @intFromEnum(len);
        const curr = std.simd.extract(vec, 0, l);
        const next = std.simd.join(dragonFn(curr), curr);

        const padding: @Vector(vec_len - 2 * l, u4) = @splat(0);
        return std.simd.join(next, padding);
    }

    fn dragonFn(vec: anytype) @TypeOf(vec) {
        const twos: @TypeOf(vec) = @splat(2);
        const fives: @TypeOf(vec) = @splat(5);
        return std.simd.reverseOrder((vec * twos) % fives);
    }

    pub fn genNext(self: *DragonVecBatch, gpa: std.mem.Allocator) !void {
        if (std.simd.firstIndexOfValue(self.batches.items[0], @intFromEnum(Direction.empty))) |fiov| {
            const len: Len = @enumFromInt(fiov);
            self.batches.items[0] = switch (len) {
                inline else => |l| a(self.batches.items[0], l),
            };
            return;
        }

        var new = try self.batches.addManyAt(gpa, 0, self.batches.items.len);
        for (self.batches.items[new.len..], 0..) |b, i| {
            new[new.len - 1 - i] = dragonFn(b);
        }
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        for (self.batches.items) |b| {
            const arr: [vec_len]u4 = b;
            for (arr) |i| {
                if (i == @intFromEnum(Direction.empty)) break;
                const ev: Direction = @enumFromInt(i);
                try writer.print("{t}, ", .{ev});
            }
            try writer.print("|", .{});
        }
    }
};

fn errorCallback(a: c_int, b: [*c]const u8) callconv(.c) void {
    std.debug.print("{} {s}\n", .{ a, b });
}

pub fn main(init: std.process.Init) !void {
    var dragon = try DragonVecBatch.init(init.gpa);
    defer dragon.deinit(init.gpa);

    for (0..16) |_| {
        try dragon.genNext(init.gpa);
    }

    const batches = dragon.batches.items;

    const Point = struct { x: f64, y: f64 };
    const vec_len = DragonVecBatch.vec_len;
    var points = try init.gpa.alloc(Point, batches.len * vec_len + 1);
    defer init.gpa.free(points);

    points[0] = .{ .x = 0, .y = 0 };

    for (batches, 0..) |b, i| {
        const arr: [vec_len]u4 = b;

        const start = i * vec_len;
        const end = (i + 1) * vec_len;
        for (points[start + 1 .. end + 1], points[start..end], arr) |*curr, prev, dir| {
            const d: DragonVecBatch.Direction = @enumFromInt(dir);
            curr.* = prev;
            switch (d) {
                .up => curr.y += 1,
                .right => curr.x += 1,
                .down => curr.y -= 1,
                .left => curr.x -= 1,
                else => {},
            }
        }
    }

    var min = points[0];
    var max = points[0];
    for (points) |p| {
        if (p.x < min.x) min.x = p.x;
        if (p.y < min.y) min.y = p.y;
        if (p.x > max.x) max.x = p.x;
        if (p.y > max.y) max.y = p.y;
    }

    for (points[0..]) |*p| {
        p.x = (p.x - min.x) / (max.x - min.x);
        p.y = (p.y - min.y) / (max.y - min.y);
    }

    const window_width = 800;
    const window_height = 800;

    _ = c.glfwSetErrorCallback(errorCallback);

    if (c.glfwInit() != 1) return error.glfwInit;
    defer c.glfwTerminate();

    const window = c.glfwCreateWindow(window_width, window_height, "Hello, World!", null, null) orelse return error.glfwCreateWindow;
    c.glfwMakeContextCurrent(window);

    c.glClearColor(0, 0, 0, 1);

    var step: usize = 0;
    while (c.glfwWindowShouldClose(window) != 1) : (step +%= 1) {
        c.glClear(c.GL_COLOR_BUFFER_BIT);

        c.glBegin(c.GL_LINE_STRIP);
        for (points, 0..) |p, i| {
            const x: f32 = @floatCast(p.x * 1.96 - 0.98);
            const y: f32 = @floatCast(p.y * 1.96 - 0.98);
            const len: f32 = @floatFromInt(points.len - 1);
            const fi: f32 = @floatFromInt(i);
            const fstep: f32 = @floatFromInt(step);
            const color = hsv2rgb(.{ .h = fi / len * 360 + fstep * 5, .s = 1, .v = 1 });
            c.glColor3f(color.r, color.g, color.b);
            c.glVertex2f(x, y);
        }
        c.glEnd();

        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }
}

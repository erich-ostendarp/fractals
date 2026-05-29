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

        var new = try alloc.alloc(Direction, self.path.items.len);
        defer alloc.free(new);

        for (new[0..], 0..) |*n, i| n.* = self.path.items[new.len - i - 1].rotCW90().invert();

        try self.path.insertSlice(alloc, 0, new);
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

fn errorCallback(a: c_int, b: [*c]const u8) callconv(.c) void {
    std.debug.print("{} {s}\n", .{ a, b });
}

const HSV = struct {
    h: f32,
    s: f32,
    v: f32,
};

const RGB = struct {
    r: f32,
    g: f32,
    b: f32,
};
pub fn rgb2hsv(rgb: RGB) HSV {
    const r = rgb.r;
    const g = rgb.g;
    const b = rgb.b;

    const cmax = @max(r, @max(g, b));
    const cmin = @min(r, @min(g, b));
    const delta = cmax - cmin;

    const v = cmax;

    const s = if (cmax == 0.0) 0.0 else delta / cmax;

    const h = blk: {
        if (delta == 0.0) break :blk 0.0;
        var raw: f32 = undefined;
        if (cmax == r)
            raw = 60.0 * @mod((g - b) / delta, 6.0)
        else if (cmax == g)
            raw = 60.0 * ((b - r) / delta + 2.0)
        else
            raw = 60.0 * ((r - g) / delta + 4.0);
        break :blk if (raw < 0.0) raw + 360.0 else raw;
    };

    return .{ .h = h, .s = s, .v = v };
}

pub fn hsv2rgb(hsv: HSV) RGB {
    const h = hsv.h;
    const s = hsv.s;
    const v = hsv.v;

    if (s == 0.0) return .{ .r = v, .g = v, .b = v };

    const sector = h / 60.0;
    const i: u32 = @intFromFloat(sector);
    const f = sector - @as(f32, @floatFromInt(i));
    const p = v * (1.0 - s);
    const q = v * (1.0 - s * f);
    const t = v * (1.0 - s * (1.0 - f));

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

fn iterate(comptime iters: usize) @Vector(1 << iters, u2) {
    if (iters == 0) return @Vector(1, u2){0};

    const half = iterate(iters - 1);
    const threes: @Vector(1 << (iters - 1), u2) = @splat(3);
    const next = half +% threes;

    return std.simd.join(next, half);
}

fn beegVector() void {
    const vec_len = 995;
    var vec: @Vector(vec_len, u4) = @splat(0);
    vec[0] = 1;

    inline for (0..std.math.log2(vec_len)) |i| {
        const len = @as(u32, 1) << @as(std.math.Log2Int(u32), @intCast(i));

        const twos: @Vector(len, u4) = @splat(2);
        const fives: @Vector(len, u4) = @splat(5);

        const extract = std.simd.extract(vec, 0, len);

        const next = std.simd.reverseOrder((extract * twos) % fives);

        const res = std.simd.join(next, extract);

        std.debug.print("{} {}\n", .{ vec_len, len });
        const zeros: @Vector(vec_len - 2 * len, u4) = @splat(0);

        vec = std.simd.join(res, zeros);

        std.debug.print("{}\n", .{res});
    }
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

    pub fn a(vec: *VecType, comptime len: u8) ?VecType {
        const extract = std.simd.extract(vec.*, 0, len);

        const twos: @Vector(len, u4) = @splat(2);
        const fives: @Vector(len, u4) = @splat(5);

        const res = std.simd.reverseOrder((extract * twos) % fives);

        if (len == vec_len) return res;

        const next = std.simd.join(res, extract);
        const zeros: @Vector(vec_len - 2 * len, u4) = @splat(0);
        vec.* = std.simd.join(next, zeros);

        return null;
    }

    pub fn genNext(self: *DragonVecBatch, gpa: std.mem.Allocator) !void {
        const batches = self.batches.items;
        if (batches.len == 1) {
            const len: usize = std.simd.firstIndexOfValue(batches[0], @intFromEnum(Direction.empty)) orelse vec_len;
            const out = switch (len) {
                inline 1, 2, 4, 8, 16, 32, 64 => |l| a(&batches[0], l),
                else => unreachable,
            };

            if (out) |o| try self.batches.append(gpa, o);
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

pub fn main(init: std.process.Init) !void {
    var dvb = try DragonVecBatch.init(init.gpa);
    defer dvb.deinit(init.gpa);

    std.debug.print("{} - {f}\n", .{ dvb.batches.items.len, dvb });
    for (0..7) |_| {
        try dvb.genNext(init.gpa);
        std.debug.print("{} - {f}\n", .{ dvb.batches.items.len, dvb });
    }

    if (true) return;

    var dragon = DragonGenerator{};
    defer dragon.deinit(init.gpa);

    for (0..20) |_| try dragon.genNext(init.gpa);

    const Point = struct { x: f64, y: f64 };
    var points = try init.gpa.alloc(Point, dragon.path.items.len + 1);
    defer init.gpa.free(points);

    points[0] = .{ .x = 0, .y = 0 };

    for (points[1..], points[0 .. points.len - 1], dragon.path.items) |*curr, prev, dir| {
        curr.* = prev;
        switch (dir) {
            .up => curr.y += 1,
            .right => curr.x += 1,
            .down => curr.y -= 1,
            .left => curr.x -= 1,
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

    const window_width = 1000;
    const window_height = 1000;

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

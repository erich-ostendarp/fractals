const std = @import("std");
const c = @import("c");

fn errorCallback(a: c_int, b: [*c]const u8) callconv(.c) void {
    std.debug.print("{} {s}\n", .{ a, b });
}

pub fn main(init: std.process.Init) !void {
    const window_width = 500;
    const window_height = 500;

    _ = c.glfwSetErrorCallback(errorCallback);

    if (c.glfwInit() != 1) return error.glfwInit;
    defer c.glfwTerminate();

    const window = c.glfwCreateWindow(window_width, window_height, "Hello, World!", null, null) orelse return error.glfwCreateWindow;
    c.glfwMakeContextCurrent(window);

    var pixels = try init.gpa.alloc(struct { u8, u8, u8 }, window_width * window_height);
    defer init.gpa.free(pixels);

    c.glClearColor(0, 0, 0, 1);

    while (c.glfwWindowShouldClose(window) != 1) {
        for (pixels[0..], 0..) |*pixel, i| {
            const a: f64 = @floatFromInt(i % window_width);
            const b: f64 = @floatFromInt(i / window_width);
            pixel.* = .{
                @intFromFloat(std.math.clamp(a, 0, 255)),
                @intFromFloat(std.math.clamp(b, 0, 255)),
                0,
            };
        }

        c.glClear(c.GL_COLOR_BUFFER_BIT);
        c.glRasterPos2i(-1, -1);
        c.glDrawPixels(window_width, window_height, c.GL_RGB, c.GL_UNSIGNED_BYTE, @ptrCast(pixels));

        c.glfwSwapBuffers(window);

        c.glfwPollEvents();
    }
}

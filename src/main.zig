const std = @import("std");

const fractals = @import("fractals");

pub fn main(init: std.process.Init) !void {
    try fractals.main(init);
}

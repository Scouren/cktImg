//! Runtime-input proof for the shared pending-pin escape query.
//! Both exports receive actual coordinates, side, net, wire pointer/count
//! and clearance. The hand implementation performs the direct bounded
//! scan; no export is linked into the layout or WASM artifacts.
//! The guarded pairs specialize all four Side values; every other input
//! stays runtime. The original runtime-side pair remains review evidence:
//! its local jump tables exceed the guard's deliberately narrow grammar.
//! These four gates make no claim about dynamic dispatch instruction order.
//!
//! Contents: private C-ABI exports for the fixed-target assembly gate.

const library = @import("library.zig");
const maze = @import("maze.zig");

// ---- private ----

export fn gen_pin_escape(x: i32, y: i32, net: u32, side: u8, wires: [*]const maze.Wire, count: usize, clear: i32, out: *library.Rect) bool {
    const result = maze.escape(.{ .at = .{ .x = x, .y = y }, .net = net, .side = @fromBackingInt(@as(u2, @truncate(side))) }, wires[0..count], clear) orelse return false;
    out.* = result;
    return true;
}

export fn hand_pin_escape(x: i32, y: i32, net: u32, side: u8, wires: [*]const maze.Wire, count: usize, clear: i32, out: *library.Rect) bool {
    const at = library.Pt{ .x = x, .y = y };
    const facing: library.Side = @fromBackingInt(@as(u2, @truncate(side)));
    const result: ?library.Rect = scan: {
        for (wires[0..count]) |w| {
            if (w.net != net or !(library.Rect.fromCorners(w.a, w.b)).contains(at)) continue;
            if (switch (facing) {
                .left => @min(w.a.x, w.b.x) < at.x,
                .right => @max(w.a.x, w.b.x) > at.x,
                .up => @min(w.a.y, w.b.y) < at.y,
                .down => @max(w.a.y, w.b.y) > at.y,
            }) break :scan null;
        }
        const v = facing.unit();
        break :scan .fromCorners(at, .{ .x = at.x + clear * v.x, .y = at.y + clear * v.y });
    };
    out.* = result orelse return false;
    return true;
}

export fn gen_pin_escape_left(x: i32, y: i32, net: u32, wires: [*]const maze.Wire, count: usize, clear: i32, out: *library.Rect) bool {
    const result = maze.escape(.{ .at = .{ .x = x, .y = y }, .net = net, .side = .left }, wires[0..count], clear) orelse return false;
    out.* = result;
    return true;
}

export fn hand_pin_escape_left(x: i32, y: i32, net: u32, wires: [*]const maze.Wire, count: usize, clear: i32, out: *library.Rect) bool {
    const result = direct(.left, x, y, net, wires[0..count], clear) orelse return false;
    out.* = result;
    return true;
}

export fn gen_pin_escape_right(x: i32, y: i32, net: u32, wires: [*]const maze.Wire, count: usize, clear: i32, out: *library.Rect) bool {
    const result = maze.escape(.{ .at = .{ .x = x, .y = y }, .net = net, .side = .right }, wires[0..count], clear) orelse return false;
    out.* = result;
    return true;
}

export fn hand_pin_escape_right(x: i32, y: i32, net: u32, wires: [*]const maze.Wire, count: usize, clear: i32, out: *library.Rect) bool {
    const result = direct(.right, x, y, net, wires[0..count], clear) orelse return false;
    out.* = result;
    return true;
}

export fn gen_pin_escape_up(x: i32, y: i32, net: u32, wires: [*]const maze.Wire, count: usize, clear: i32, out: *library.Rect) bool {
    const result = maze.escape(.{ .at = .{ .x = x, .y = y }, .net = net, .side = .up }, wires[0..count], clear) orelse return false;
    out.* = result;
    return true;
}

export fn hand_pin_escape_up(x: i32, y: i32, net: u32, wires: [*]const maze.Wire, count: usize, clear: i32, out: *library.Rect) bool {
    const result = direct(.up, x, y, net, wires[0..count], clear) orelse return false;
    out.* = result;
    return true;
}

export fn gen_pin_escape_down(x: i32, y: i32, net: u32, wires: [*]const maze.Wire, count: usize, clear: i32, out: *library.Rect) bool {
    const result = maze.escape(.{ .at = .{ .x = x, .y = y }, .net = net, .side = .down }, wires[0..count], clear) orelse return false;
    out.* = result;
    return true;
}

export fn hand_pin_escape_down(x: i32, y: i32, net: u32, wires: [*]const maze.Wire, count: usize, clear: i32, out: *library.Rect) bool {
    const result = direct(.down, x, y, net, wires[0..count], clear) orelse return false;
    out.* = result;
    return true;
}

inline fn direct(comptime facing: library.Side, x: i32, y: i32, net: u32, wires: []const maze.Wire, clear: i32) ?library.Rect {
    const at = library.Pt{ .x = x, .y = y };
    for (wires) |w| {
        if (w.net != net or !(library.Rect.fromCorners(w.a, w.b)).contains(at)) continue;
        if (switch (facing) {
            .left => @min(w.a.x, w.b.x) < at.x,
            .right => @max(w.a.x, w.b.x) > at.x,
            .up => @min(w.a.y, w.b.y) < at.y,
            .down => @max(w.a.y, w.b.y) > at.y,
        }) return null;
    }
    const v = facing.unit();
    return .fromCorners(at, .{ .x = at.x + clear * v.x, .y = at.y + clear * v.y });
}

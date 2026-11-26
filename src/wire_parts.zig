//! Two already-qualified physical net parts -> ordinary named ink, atomically.
//! Cites the complete four-side CT and linked-load output source consumers.
//! Selection, actual-pin mapping, caller intent and success flags remain in
//! each caller. This cold seam changes no trunk cost or thinning policy.
//!
//! Data: borrowed Canvas/net/pin slices; one six-usize append checkpoint.
//! Canvas/Schematic own all output. No retained graph, allocation table, ABI
//! change or hot-path claim. Failure restores the current net's append rows.
//!
//! Contents: Checkpoint.take/restore, draw, symbol; private component/contact.

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const sch = @import("schematic.zig");
const library = @import("library.zig");
const canvas = @import("canvas.zig");
const trunk = @import("trunk.zig");
const Canvas = canvas.Canvas;
const Rect = library.Rect;

/// Append-only Canvas plus generated pin/coordinate lengths. Existing rows
/// must remain unchanged while this checkpoint is live.
pub const Checkpoint = struct {
    ink: Canvas.Checkpoint,
    pins: usize,
    xy: usize,

    /// Saves the current append lengths without allocation.
    pub fn take(c: *const Canvas) Checkpoint {
        return .{ .ink = c.save(), .pins = c.s.pins.len, .xy = c.xy.items.len };
    }
    /// Truncates generated symbols and ink, rebinding xy even after OOM.
    pub fn restore(saved: Checkpoint, c: *Canvas) void {
        c.s.pins.shrinkRetainingCapacity(saved.pins);
        c.s.nodes.shrinkRetainingCapacity(saved.ink.nodes);
        c.xy.shrinkRetainingCapacity(saved.xy);
        c.s.xy = c.xy.items; // Allocation may have moved xy before leaf rebound it.
        c.restore(saved.ink);
    }
};

comptime {
    assert(@sizeOf(Checkpoint) == 6 * @sizeOf(usize));
}

/// Draws a then b using ordinary trunk/leaf, with one bound symbol per part.
/// Part b always carries its name; end chooses a's ordinary terminal kind.
/// Any contact between the parts, decline or OOM restores all appended rows.
pub fn draw(c: *Canvas, net: u32, a: []const u32, b: []const u32, end: trunk.End) Allocator.Error!bool {
    assert(a.len != 0 and b.len != 0);
    assert(a.len + b.len <= c.s.pins.len);
    const output = end == .port;
    for (a) |p| for (b) |q| if (canvas.pinAt(c.s, p).eql(canvas.pinAt(c.s, q))) return false;
    const saved = Checkpoint.take(c);
    var accepted = false;
    defer if (!accepted) saved.restore(c);
    if (!try component(c, net, a, output)) return false;
    const middle = c.segs.items.len;
    if (!try component(c, net, b, false)) return false;
    if (contact(c, saved.ink.segs, middle, b) or contact(c, middle, c.segs.items.len, a)) return false;
    for (c.segs.items[saved.ink.segs..middle]) |left| for (c.segs.items[middle..]) |right| {
        if (Rect.fromCorners(left.a, left.b).intersects(Rect.fromCorners(right.a, right.b))) return false;
    };
    accepted = true;
    return true;
}

/// Certifies exactly one newly generated, correctly bound symbol attached
/// to this part's real pins or new segments. name requires a label node;
/// port permits the ordinary terminal or its named fallback.
pub fn symbol(c: *const Canvas, net: u32, pins: []const u32, pin_from: usize, seg_from: usize, end: trunk.End) bool {
    const named = end == .name;
    if (c.s.pins.len != pin_from + 1) return false;
    const pin = c.s.pins.get(pin_from);
    if (pin.net != net or pin.device != sch.none) return false;
    const node = c.s.nodes.get(pin.home);
    if (node.ref != net or node.kind == .device or (named and node.kind != .label)) return false;
    const at = canvas.pinAt(c.s, @intCast(pin_from));
    for (pins) |p| if (at.eql(canvas.pinAt(c.s, p))) return true;
    for (c.segs.items[seg_from..]) |segment| if (segment.net == net and Rect.fromCorners(segment.a, segment.b).contains(at)) return true;
    return false;
}

// ---- private ----

fn component(c: *Canvas, net: u32, pins: []const u32, output: bool) Allocator.Error!bool {
    const first_pin = c.s.pins.len;
    const first_seg = c.segs.items.len;
    if (pins.len == 1) {
        try c.labelAt(pins[0]);
    } else if (!try trunk.draw(c, net, pins, if (output) .port else .name)) return false;
    return symbol(c, net, pins, first_pin, first_seg, if (output) .port else .name);
}

fn contact(c: *const Canvas, from: usize, end: usize, pins: []const u32) bool {
    for (c.segs.items[from..end]) |segment| {
        const r = Rect.fromCorners(segment.a, segment.b);
        for (pins) |p| if (r.contains(canvas.pinAt(c.s, p))) return true;
    }
    return false;
}

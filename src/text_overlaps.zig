//! Where a drawing's text lands on something else. In: a finished `Placed`
//! and its library. Out: one finding per piece of text and thing it lies
//! on: a symbol not its own, another piece of text, or a wire of a net not
//! its own. Text is every name a renderer writes: a device's name where
//! `geom.refdesAnchors` puts it, a port's, a rail's (a ground rail's only
//! where `geom.namesRail`) and a label's where `geom.nameRect` puts it.
//! Boxes are estimated, `geom.char_w` a character by `geom.text_h` plus
//! `geom.descent`, and shrunk a unit each way, so text that only touches
//! counts as clear.
//!
//! Human Rules:
//! - text_overlaps.1 (choice) A name lies clear of every symbol but its own
//!   device's, of every other name, and of every wire of another net (a
//!   device's name, of every wire; a label, of its own net's wire too):
//!   text on a symbol, a name or a wire reads as part of it. Not yet a guarantee: the report lists the
//!   findings apart from its `gates` (`tests/text_overlaps.zig` holds the
//!   decks known to break it). `find`
//!
//! - text_overlaps.2 (choice) A label whose name lies on something turns
//!   (a wire of its own net too) to the first side of right, left, above,
//!   below that is clear and that no wire of its net leaves; with none
//!   clear it keeps its side. `settleLabels`
//!
//! Contents:
//! - `pub const Over = enum`, `pub const Of = enum`, `pub const Overlap = struct`
//! - `pub fn find(gpa: Allocator, out: *std.ArrayList(Overlap), p: *const Placed, lib: *const Library) Allocator.Error!void`
//! - `pub fn settleLabels(gpa: Allocator, p: *const Placed, labels: []placed.Label, lib: *const Library) Allocator.Error!void`

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const library = @import("library.zig");
const placed = @import("placed.zig");
const geom = @import("geom.zig");
const checks = @import("checks.zig");

const Rect = library.Rect;
const Side = library.Side;
const Library = library.Library;
const Placed = placed.Placed;

/// What a name is the name of.
pub const Of = enum { device, port, rail, label };
/// What a name lies on.
pub const Over = enum { symbol, text, wire };

pub const Overlap = struct {
    of: Of,
    /// The text: a device's name or a net's.
    text: []const u8,
    /// The box the text was estimated to fill.
    box: Rect,
    over: Over,
    /// The symbol's device, the other name's text, or the wire's net, by name.
    other: []const u8,
};

/// A name and its box: `dev` the device it belongs to (none for a label),
/// `net` the net it names (none for a device's name).
const Name = struct {
    of: Of,
    box: Rect,
    dev: u32,
    net: u32,

    fn text(t: Name, p: *const Placed) []const u8 {
        return if (t.of == .device) p.dev_name[t.dev] else p.net_name[t.net];
    }
    fn over(t: Name, what: Over, other: []const u8, p: *const Placed) Overlap {
        return .{ .of = t.of, .text = t.text(p), .box = t.box, .over = what, .other = other };
    }
};

const Wire = struct { box: Rect, net: u32 };

/// Appends a finding for every name of `p` and thing it lies on, names in
/// order device names, then ports and rails by device, then labels.
/// `lib` is the library `p` was drawn with.
// ponytail: every name against every box, quadratic; fine at cell sizes.
pub fn find(gpa: Allocator, out: *std.ArrayList(Overlap), p: *const Placed, lib: *const Library) Allocator.Error!void {
    const before = out.items.len;
    var names: std.ArrayList(Name) = .empty;
    defer names.deinit(gpa);
    try collect(gpa, &names, p, lib);
    var wires: std.ArrayList(Wire) = .empty;
    defer wires.deinit(gpa);
    for (0..p.netCount()) |n| {
        var it = p.segments(n);
        while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
            try wires.append(gpa, .{ .box = .fromCorners(a, b), .net = @intCast(n) });
        };
    }
    for (names.items, 0..) |t, i| {
        const box = t.box.grow(-1);
        for (0..p.deviceCount()) |d| {
            if (d == t.dev or !box.intersects(p.deviceRect(lib, d).grow(-1))) continue;
            try out.append(gpa, t.over(.symbol, symbolName(p, d), p));
        }
        for (names.items[i + 1 ..]) |u| {
            if (box.intersects(u.box.grow(-1))) try out.append(gpa, t.over(.text, u.text(p), p));
        }
        // Once per net it lies on.
        var last: u32 = placed.no_net;
        for (wires.items) |w| {
            // A label on its own net's wire too: it reads as a second wire.
            if ((w.net == t.net and t.of != .label) or w.net == last or !box.intersects(w.box)) continue;
            last = w.net;
            try out.append(gpa, t.over(.wire, p.net_name[w.net], p));
        }
    }
    assert(out.items.len >= before);
}

/// Turns each label of `p` whose name lies on a symbol, another net name
/// or a wire (its own net's too) to the first side of right, left, above, below
/// that is clear and that no wire of its net leaves, label by label, each
/// judged against the sides settled before it; a label with no clear side
/// keeps its own. `labels` is `p.labels`, writable; `lib` the library `p`
/// was drawn with. Device names are placed after, clear of these.
pub fn settleLabels(gpa: Allocator, p: *const Placed, labels: []placed.Label, lib: *const Library) Allocator.Error!void {
    assert(labels.ptr == p.labels.ptr and labels.len == p.labels.len);
    var names: std.ArrayList(geom.NetName) = .empty;
    defer names.deinit(gpa);
    try geom.netNames(gpa, &names, p, lib);
    assert(names.items.len >= labels.len);
    const first = names.items.len - labels.len;
    for (labels, names.items[first..], first..) |*l, *t, k| {
        assert(t.dev == geom.no_dev and t.net == l.net);
        if (clear(p, lib, names.items, k)) continue;
        const taken = checks.ways(p, l.net, l.at);
        const name = p.net_name[l.net];
        for ([_]Side{ .right, .left, .up, .down }) |s| {
            if (s == l.side or taken & @as(u4, 1) << @backingInt(s) != 0) continue;
            t.box = geom.nameRect(l.at, s, name, geom.name_gap);
            if (!clear(p, lib, names.items, k)) continue;
            l.side = s;
            break;
        } else t.box = geom.nameRect(l.at, l.side, name, geom.name_gap);
    }
}

// ---- private ----

/// Every name `p` writes, in `find`'s order.
fn collect(gpa: Allocator, names: *std.ArrayList(Name), p: *const Placed, lib: *const Library) Allocator.Error!void {
    const anchors = try geom.refdesAnchors(gpa, p, lib);
    defer gpa.free(anchors);
    for (anchors, 0..) |at, d| {
        if (p.dev_name[d].len == 0) continue;
        try names.append(gpa, .{ .of = .device, .box = geom.refdesRect(at, p.dev_name[d]), .dev = @intCast(d), .net = placed.no_net });
    }
    var nets: std.ArrayList(geom.NetName) = .empty;
    defer nets.deinit(gpa);
    try geom.netNames(gpa, &nets, p, lib);
    for (nets.items) |t| {
        const of: Of = if (t.dev == geom.no_dev) .label else switch (lib.at(p.dev_class[t.dev]).role) {
            .power_rail, .ground_rail => .rail,
            else => .port,
        };
        try names.append(gpa, .{ .of = of, .box = t.box, .dev = t.dev, .net = t.net });
    }
}

/// A device's name, or for a rail or port the layout added, its net's.
fn symbolName(p: *const Placed, d: usize) []const u8 {
    if (p.dev_name[d].len > 0) return p.dev_name[d];
    const net = p.pin_net[p.dev_pin0[d]];
    return if (net == placed.no_net) "" else p.net_name[net];
}

/// Whether label `k` of `names` (`geom.netNames` of `p`) lies clear of
/// every symbol, every other name and every wire, its own net's too.
fn clear(p: *const Placed, lib: *const Library, names: []const geom.NetName, k: usize) bool {
    const t = names[k];
    const box = t.box.grow(-1);
    for (0..p.deviceCount()) |d| {
        if (d != t.dev and box.intersects(p.deviceRect(lib, d).grow(-1))) return false;
    }
    for (names, 0..) |u, j| {
        if (j != k and box.intersects(u.box.grow(-1))) return false;
    }
    // Its own net's wires too: a name along its wire reads as two wires.
    for (0..p.netCount()) |n| {
        var it = p.segments(n);
        while (it.next()) |poly| for (poly[0 .. poly.len - 1], poly[1..]) |a, b| {
            if (box.intersects(.fromCorners(a, b))) return false;
        };
    }
    return true;
}

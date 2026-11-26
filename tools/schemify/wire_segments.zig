//! Turns a placed net into Schemify wire records and selects a lattice point for its name.
//!
//! Contents:
//! - `pub fn merged`, `pub fn onSeg`, `pub fn spot`

const std = @import("std");
const engine = @import("NetlistParser");
const geometry = engine.wire_geometry;
const Pt = engine.Pt;
const Range = @import("spice.zig").Range;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

const Seg = [4]i32;
const P = [2]i32;

const Line = struct {
    at: i64,
    lo: i32,
    hi: i32,
    direction: geometry.Direction,

    fn point(line: Line, t: i32) Pt {
        return switch (line.direction) {
            .horizontal => .{ .x = t, .y = @intCast(line.at) },
            .vertical => .{ .x = @intCast(line.at), .y = t },
            .down_right => .{ .x = t, .y = @intCast(line.at + t) },
            .up_right => .{ .x = t, .y = @intCast(line.at - t) },
        };
    }
};
comptime {
    std.debug.assert(@sizeOf(Line) == 24);
}

/// One net’s cardinal or 45-degree segments without overlaps: each normalized so `(x1, y1) <
/// (x2, y2)` (the format's wire order), zero-length ones dropped, and collinear ones that
/// overlap cut at every original endpoint into disjoint pieces. Every original endpoint
/// stays an endpoint, so connectivity is unchanged (netlist spec §3: joining two pieces
/// through a junction would turn it into an interior crossing, which does not connect).
pub fn merged(a: Allocator, segs: []const Seg) Allocator.Error![]const Seg {
    var lines: ArrayList(Line) = .empty;
    for (segs) |s0| {
        const swap = s0[2] < s0[0] or (s0[2] == s0[0] and s0[3] < s0[1]);
        const s: Seg = if (swap) .{ s0[2], s0[3], s0[0], s0[1] } else s0;
        if (s[0] == s[2] and s[1] == s[3]) continue;
        const p: Pt = .{ .x = s[0], .y = s[1] };
        const q: Pt = .{ .x = s[2], .y = s[3] };
        const direction = geometry.direction(p, q).?; // engine’s wire domain
        try lines.append(a, .{
            .direction = direction,
            .at = direction.offset(p),
            .lo = if (direction == .vertical) p.y else p.x,
            .hi = if (direction == .vertical) q.y else q.x,
        });
    }
    const ls = lines.items;
    std.sort.heap(Line, ls, {}, lineLess);
    var out: ArrayList(Seg) = try .initCapacity(a, ls.len);
    var cuts: ArrayList(i32) = .empty;
    var k: usize = 0;
    while (k < ls.len) {
        const direction = ls[k].direction;
        const at = ls[k].at;
        var end = k;
        while (end < ls.len and ls[end].direction == direction and ls[end].at == at) end += 1;
        cuts.clearRetainingCapacity();
        for (ls[k..end]) |l| try cuts.appendSlice(a, &.{ l.lo, l.hi });
        std.sort.heap(i32, cuts.items, {}, std.sort.asc(i32));
        // Sweep the union of the intervals; emit the pieces between consecutive cuts.
        var lo = ls[k].lo;
        var hi = ls[k].hi;
        for (k + 1..end + 1) |j| {
            const sentinel = j == end;
            if (!sentinel and ls[j].lo <= hi) {
                hi = @max(hi, ls[j].hi);
                continue;
            }
            var prev: ?i32 = null;
            for (cuts.items) |cut| {
                if (cut < lo or cut > hi or (prev != null and prev.? == cut)) continue;
                if (prev) |p| {
                    const a0 = ls[k].point(p);
                    const b0 = ls[k].point(cut);
                    try out.append(a, .{ a0.x, a0.y, b0.x, b0.y });
                }
                prev = cut;
            }
            if (!sentinel) {
                lo = ls[j].lo;
                hi = ls[j].hi;
            }
        }
        k = end;
    }
    for (out.items) |s| assert(s[0] < s[2] or (s[0] == s[2] and s[1] < s[3]));
    return out.items;
}

/// Whether point `p` lies on segment `w` (normalized, as `merged` leaves it), ends included.
pub fn onSeg(p: P, w: Seg) bool {
    return geometry.contains(.{ .x = w[0], .y = w[1] }, .{ .x = w[2], .y = w[3] }, .{ .x = p[0], .y = p[1] });
}

/// Where to write a net's name on its wires `wires[mine]`: the middle of one of its four
/// longest segments that no other net's wire passes through (a name there would join that
/// wire too). Null when every candidate tried is crossed.
pub fn spot(a: Allocator, wires: []const Seg, mine: Range) Allocator.Error!?P {
    const order = try a.alloc(u32, mine.len());
    for (order, mine.lo..) |*o, i| o.* = @intCast(i);
    std.sort.heap(u32, order, wires, struct {
        fn lt(ws: []const Seg, x: u32, y: u32) bool {
            const lx = span(ws[x]);
            const ly = span(ws[y]);
            return lx > ly or (lx == ly and x < y);
        }
    }.lt);
    for (order[0..@min(order.len, 4)]) |i| {
        const w = wires[i];
        const steps: i64 = @intCast(span(w) / 2);
        const x: i64 = w[0];
        const y: i64 = w[1];
        const m: P = .{
            @intCast(x + steps * std.math.sign(@as(i64, w[2]) - x)),
            @intCast(y + steps * std.math.sign(@as(i64, w[3]) - y)),
        };
        const clear = for (wires, 0..) |o, j| {
            if ((j < mine.lo or j >= mine.hi) and onSeg(m, o)) break false;
        } else true;
        if (clear) return m;
    }
    return null;
}

// ---- private ----

fn lineLess(_: void, x: Line, y: Line) bool {
    if (x.direction != y.direction) return @backingInt(x.direction) < @backingInt(y.direction);
    if (x.at != y.at) return x.at < y.at;
    if (x.lo != y.lo) return x.lo < y.lo;
    return x.hi < y.hi;
}

fn span(w: Seg) u64 {
    return @max(@abs(@as(i64, w[2]) - w[0]), @abs(@as(i64, w[3]) - w[1]));
}

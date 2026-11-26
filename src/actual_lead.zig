//! Actual attached block leads -> a verified outward world side.
//!
//! Human Rules:
//! - actual_lead.1 (invariant) A visible cardinal terminal must attach to
//!   its own single closed body at the first boundary reached. Every body
//!   point/disk lies behind the tip; actual direction agrees with metadata.
//!   Bias peers and paired-output tanks share this cold frame certificate.
//!   No family, label or bounding-box proximity substitutes for attachment.
//!
//! Data: borrowed class strokes and one u8 pin index (device pin-count
//! width) in; optional Side out. No allocation, retained state or hot-path
//! dispatch. This is the exact second-use extraction of bias leadSide.
//!
//! Contents: `leadSide`, private projection.

const sch = @import("schematic.zig");
const library = @import("library.zig");
const Pt = library.Pt;
const Rect = library.Rect;
const Side = library.Side;

/// Returns the actual outward side of a visible, attached block terminal.
/// The settled device belongs to s; callers retain all rows and class ink.
/// Unsupported/multiple body outlines or intervening body edges return null.
pub fn leadSide(s: *const sch.Schematic, d: u32, pin: u8) ?Side {
    const info = s.devices.slice();
    const c = s.lib.at(info.items(.class)[d]);
    if (pin >= s.device_pin_count[d] or !c.shows(pin)) return null;
    const t = c.terminals[pin].at;
    var attachment: ?Pt = null;
    for (c.draw) |op| if (op == .line) {
        const line = op.line;
        const p = if (line.a.eql(t)) line.b else if (line.b.eql(t)) line.a else continue;
        if (attachment != null or p.eql(t) or (p.x != t.x and p.y != t.y)) return null;
        attachment = p;
    };
    const delta = t.sub(attachment orelse return null);
    const side = Side.of(delta).?;
    for (c.draw) |op| switch (op) {
        .circle, .filled_circle => |circular| if (project(circular.c.sub(t), side) + circular.r >= 0) return null,
        else => {},
    };
    var body = false;
    var attached = false;
    for (c.draw) |op| if (op == .polyline) {
        for (op.polyline) |p| if (project(p.sub(t), side) >= 0) return null;
        const ps = op.polyline;
        if (ps.len < 4 or !ps[0].eql(ps[ps.len - 1]) or body) return null;
        body = true;
        for (ps[0 .. ps.len - 1], ps[1..]) |a, b| {
            const p = attachment.?;
            const cross = @as(i64, p.x - a.x) * (b.y - a.y) - @as(i64, p.y - a.y) * (b.x - a.x);
            attached = attached or (cross == 0 and Rect.fromCorners(a, b).contains(p));
            // The attachment must be the first body boundary reached.
            // A diagonal may meet it; no edge may touch the open lead.
            const horizontal = side.isHorizontal();
            const transverse = if (horizontal) t.y else t.x;
            const ta = if (horizontal) a.y else a.x;
            const tb = if (horizontal) b.y else b.x;
            if (transverse < @min(ta, tb) or transverse > @max(ta, tb)) continue;
            const from_tip = @as(i64, t.x - a.x) * (b.y - a.y) - @as(i64, t.y - a.y) * (b.x - a.x);
            if ((cross < 0 and from_tip > 0) or (cross > 0 and from_tip < 0)) return null;
            if (cross == 0 and from_tip == 0) {
                const lo = if (horizontal) @min(t.x, p.x) else @min(t.y, p.y);
                const hi = if (horizontal) @max(t.x, p.x) else @max(t.y, p.y);
                const ea = if (horizontal) a.x else a.y;
                const eb = if (horizontal) b.x else b.y;
                if (@min(ea, eb) < hi and @max(ea, eb) > lo) return null;
            }
        }
    };
    const o = info.items(.orient)[d];
    const actual = Side.of(o.apply(delta)).?;
    return if (body and attached and c.side(pin, o) == actual) actual else null;
}


// ---- private ----

fn project(p: Pt, direction: Side) i32 {
    const v = direction.unit();
    return p.x * v.x + p.y * v.y;
}

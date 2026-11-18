//! Final drawing certificates for the caller's common reflection axis.
//!
//! Contents:
//! - `pub fn plane(nl: *const Netlist, st: *const Structure, sk: *const Skeleton, p: *const Placed) ?i64`
//! - `pub fn shows(p: *const Placed, h: Hint, axis: ?i64) bool`

const checks = @import("checks.zig");
const structure = @import("structure.zig");
const Netlist = @import("netlist.zig").Netlist;
const Structure = structure.Structure;
const Skeleton = @import("skeleton.zig").Skeleton;
const Placed = @import("placed.zig").Placed;
const Hint = @import("hints.zig").Hint;

const Witnesses = struct {
    value: ?i64 = null,
    divided: bool = false,

    fn add(w: *Witnesses, x: i64) void {
        if (w.value) |old| w.divided = w.divided or old != x;
        w.value = x;
    }

    fn unique(w: Witnesses) ?i64 {
        return if (w.divided) null else w.value;
    }
};

/// Twice the final axis x implied by the surviving lattice reflection.
/// Complete reflected pairs establish it. When pair axes disagree, a common
/// physical center of the retained axis devices can distinguish the plane.
pub fn plane(nl: *const Netlist, st: *const Structure, sk: *const Skeleton, p: *const Placed) ?i64 {
    const lattice = sk.axis2 orelse return null;
    const names = nl.graph.edges.items(.name);
    var centers: Witnesses = .{};
    for (st.device_mate, 0..) |mate, d| {
        if (mate != d or !sk.drawn[d] or 2 * @as(i64, sk.x[d]) != lattice) continue;
        const a = checks.deviceIn(p, names[d]) orelse continue;
        centers.add(2 * @as(i64, p.dev_pos[a].x));
    }
    const center = centers.unique();
    var pairs: Witnesses = .{};
    var has_pair = false;
    var agrees = false;
    for (st.device_mate, 0..) |mate, d| {
        if (mate == structure.none or mate <= d or !sk.drawn[d] or !sk.drawn[mate]) continue;
        if (@as(i64, sk.x[d]) + sk.x[mate] != lattice) continue;
        has_pair = true;
        const a = checks.deviceIn(p, names[d]) orelse continue;
        const b = checks.deviceIn(p, names[mate]) orelse continue;
        if (frame(p, a, b)) |axis| {
            pairs.add(axis);
            agrees = agrees or center == axis;
        }
    }
    return pairs.unique() orelse if (!has_pair or agrees) center else null;
}

/// Whether the named origins and corresponding physical terminals satisfy
/// the requested reflection, or the single axis device sits on that plane.
pub fn shows(p: *const Placed, h: Hint, axis: ?i64) bool {
    const common = axis orelse return false;
    const a = checks.deviceIn(p, h.args[0]) orelse return false;
    if (h.verb == .axis) return 2 * @as(i64, p.dev_pos[a].x) == common;
    const b = checks.deviceIn(p, h.args[1]) orelse return false;
    if (a == b) return 2 * @as(i64, p.dev_pos[a].x) == common;
    return frame(p, a, b) == common;
}

// ---- private ----

/// Twice the mirror x of two full, ordered device frames.
fn frame(p: *const Placed, a: usize, b: usize) ?i64 {
    const left = p.dev_pos[a];
    const right = p.dev_pos[b];
    if (left.y != right.y) return null;
    const axis = @as(i64, left.x) + right.x;
    const af, const ae = p.pinRange(a);
    const bf, const be = p.pinRange(b);
    if (ae - af != be - bf) return null;
    for (p.pin_xy[af..ae], p.pin_xy[bf..be]) |u, v| {
        if (u.y != v.y or @as(i64, u.x) + v.x != axis) return null;
    }
    return axis;
}

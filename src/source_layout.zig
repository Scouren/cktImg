//! Complete local rooms with original mixed-device ownership.
//!
//! Contents:
//! - `pub const Owner`, `pub fn collect`, `pub fn arrange`, `pub fn intact`
const std = @import("std");
const netlist = @import("netlist.zig");
const bridge = @import("source_bridge.zig");
const folded = @import("folded_bank.zig");
const mixer = @import("mixer_bank.zig");

/// Ordered handles refer to the selected graph and include every device in the room.
pub const Owner = union(enum) { bridge: bridge.Request, mixer: mixer.Request, folded: folded.Request };

/// Binds a complete original cell to its source and passive attachments.
pub fn collect(a: std.mem.Allocator, raw: []const u8, nl: *const netlist.Netlist) !?Owner {
    if (try bridge.fromSource(a, raw, nl)) |row| return .{ .bridge = row };
    const row: Owner = if (try mixer.collect(a, raw, nl)) |m| .{ .mixer = m } else if (try folded.collect(a, raw, nl)) |f| .{ .folded = f } else return null;
    const switches = switch (row) {
        .mixer => |*m| m.devices[5..9],
        .folded => |*f| f.devices[4..8],
        .bridge => unreachable,
    };
    const graph = &nl.graph;
    var mos: [8]netlist.EdgeId = undefined;
    var n: usize = 0;
    for (graph.edges.items(.kind), 0..) |kind, i| if (kind == .mosfet) {
        if (n == mos.len) return null;
        mos[n] = netlist.EdgeId.from(i);
        n += 1;
    };
    const rects = @import("switch_rectangles.zig");
    return if (rects.alone(try rects.fromDevices(a, nl, mos[0..n]), switches)) row else null;
}

/// Applies the admitted room before routing using the resolved caller requests.
pub fn arrange(row: Owner, nl: *const netlist.Netlist, s: *@import("schematic.zig").Schematic, sk: *const @import("skeleton.zig").Skeleton, at: [][2]f32, verdicts: []const @import("hints.zig").Verdict) bool {
    return switch (row) {
        .bridge => |r| bridge.arrange(nl, s, sk, at, r, verdicts),
        .mixer => |r| mixer.arrange(nl, s, sk, at, r, verdicts),
        .folded => |r| folded.arrange(nl, s, sk, at, r, verdicts),
    };
}

/// Checks the final emitted route against its owner-specific physical contract.
pub fn intact(row: Owner, p: *const @import("placed.zig").Placed, nl: *const netlist.Netlist, lib: *const @import("library.zig").Library) bool {
    return switch (row) {
        .bridge => |r| bridge.intact(p, nl, r, lib.unit),
        inline .mixer, .folded => |r| clear: {
            for (r.devices) |d| if (!@import("parent_stages.zig").clearDevice(p, lib, nl, d)) break :clear false;
            break :clear true;
        },
    };
}

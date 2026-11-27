//! Filled-circle interaction with private bias placement.
//! Caller body ink bounds the inferred relative-placement contract.
//!
//! Contents: literal source/control fixture, caller body, then regression.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");

const ag2436 =
    \\ag-2436 private bias peer
    \\.model nch nmos
    \\.model pch pmos
    \\.subckt bias vdd vss vb1 nb
    \\.ends bias
    \\.subckt error_amp vdd vss vref nb out
    \\.ends error_amp
    \\m1 net3 net4 vin vdd pch l=0.15 w=1 nf=1 m=1
    \\m2 net1 net1 net3 vdd pch l=0.15 w=1 nf=1 m=1
    \\m3 net1 nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mbias verr nb vss vss nch l=0.15 w=1 nf=1 m=1
    \\mchg net2 pb vin vdd pch l=0.15 w=1 nf=1 m=1
    \\mctrl verr net1 vout vdd pch l=0.15 w=1 nf=1 m=1
    \\mgen net5 net5 vss vss nch l=0.15 w=1 nf=1 m=1
    \\minj verr net5 vss vss nch l=0.15 w=1 nf=1 m=1
    \\mres vout verr vin vdd pch l=0.15 w=1 nf=1 m=1
    \\msen net5 net4 net2 vdd pch l=0.15 w=1 nf=1 m=1
    \\x1 vdd vss vref net0 net4 error_amp
    \\x2 vdd vss vb1 net0 bias
    \\*@ weak role verr output
    \\
;

const custom_peer: np.Class = .{
    .name = "offset_bias_peer",
    .terminals = &.{
        .{ .name = "vdd", .at = .{ .x = 90, .y = -80 }, .side = .up },
        .{ .name = "vss", .at = .{ .x = 100, .y = 100 }, .side = .down },
        .{ .name = "vb1", .at = .{ .x = 60, .y = 100 }, .side = .down },
        .{ .name = "nb", .at = .{ .x = -10, .y = 25 }, .side = .left },
    },
    .draw = &.{
        .{ .polyline = &.{ .{ .x = 30, .y = -40 }, .{ .x = 150, .y = -40 }, .{ .x = 150, .y = 60 }, .{ .x = 30, .y = 60 }, .{ .x = 30, .y = -40 } } },
        .{ .line = .{ .a = .{ .x = 90, .y = -80 }, .b = .{ .x = 90, .y = -40 } } },
        .{ .line = .{ .a = .{ .x = 100, .y = 100 }, .b = .{ .x = 100, .y = 60 } } },
        .{ .line = .{ .a = .{ .x = 60, .y = 100 }, .b = .{ .x = 60, .y = 60 } } },
        .{ .line = .{ .a = .{ .x = -10, .y = 25 }, .b = .{ .x = 30, .y = 25 } } },
    },
};

test "filled-circle body bounds: a filled disk beyond the bias tip preserves ordinary placement" {
    // Oracle: the public caller body and the ordinary renamed-family
    // control. This disk lies wholly outside the NB tip, so the peer must
    // not be reoriented as though all its body ink were behind that tip.
    // The literal rectangle and its actual lead remain unchanged.
    if (comptime @hasField(np.library.DrawOp, "filled_circle")) {
        const gpa = testing.allocator;
        const lib = try support.library(gpa);
        defer support.freeLibrary(gpa, lib);
        var ops: [custom_peer.draw.len + 1]np.library.DrawOp = undefined;
        @memcpy(ops[0..custom_peer.draw.len], custom_peer.draw);
        ops[custom_peer.draw.len] = .{ .filled_circle = .{ .c = .{ .x = -30, .y = 25 }, .r = 15 } };
        const disk = ops[custom_peer.draw.len].filled_circle;
        try testing.expect(disk.c.x + disk.r < custom_peer.terminals[3].at.x);
        const id = try lib.register(.{ .name = "outside_filled_body", .terminals = custom_peer.terminals, .draw = &ops });
        const src = ag2436 ++ "*@ class x2 outside_filled_body\n";
        const renamed = try std.mem.replaceOwned(u8, gpa, src, " bias", " opaque");
        defer gpa.free(renamed);
        for ([_]bool{ false, true }) |compact| {
            const cfg: np.Config = .{ .layout = .{ .compact = compact } };
            var actual = try np.place(gpa, &cfg, lib, &.{src}, null);
            defer actual.deinit();
            var ordinary = try np.place(gpa, &cfg, lib, &.{renamed}, null);
            defer ordinary.deinit();
            const x = np.checks.deviceIn(&actual, "x2").?;
            const y = np.checks.deviceIn(&ordinary, "x2").?;
            try testing.expectEqual(np.Orient.r0, actual.dev_orient[x]);
            try testing.expectEqual(ordinary.dev_orient[y], actual.dev_orient[x]);
            try testing.expectEqual(ordinary.dev_pos[y], actual.dev_pos[x]);
            try testing.expectEqualDeep(@as([]const np.library.DrawOp, &ops), lib.at(id).draw);
        }
    } else try testing.expect(false);
}

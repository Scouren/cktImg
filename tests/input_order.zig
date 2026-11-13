//! Competing input branches -> card-order-independent named placement.
//! Oracle: permuting cards changes no device, net, value or caller request.

const std = @import("std");
const np = @import("NetlistParser");
const support = @import("support.zig");

test "input branches: competing sources retain named pins under card permutation" {
    const prefix = "Two source branches\n.model nch nmos\n" ++
        "M1 out gate 0 0 nch\nRD vdd out 1k\n" ++
        "*@ symmetry off\n*@ weak driver v1 inline\n*@ weak driver v2 inline\n";
    const first = prefix ++ "R1 a gate 1k\nV1 a 0 1\nR2 b gate 2k\nV2 b 0 2\n";
    const second = prefix ++ "V2 b 0 2\nR2 b gate 2k\nV1 a 0 1\nR1 a gate 1k\n";
    const gpa = std.testing.allocator;
    const lib = try support.library(gpa);
    defer support.freeLibrary(gpa, lib);
    for ([_]bool{ false, true }) |compact| {
        var a = try np.place(gpa, &.{ .layout = .{ .compact = compact } }, lib, &.{first}, null);
        defer a.deinit();
        var b = try np.place(gpa, &.{ .layout = .{ .compact = compact } }, lib, &.{second}, null);
        defer b.deinit();
        for ([_][]const u8{ "m1", "rd", "r1", "v1", "r2", "v2" }) |name| {
            const i = np.checks.deviceIn(&a, name).?;
            const j = np.checks.deviceIn(&b, name).?;
            errdefer std.debug.print("input permutation: {s}, compact={}\n", .{ name, compact });
            try std.testing.expectEqual(a.dev_orient[i], b.dev_orient[j]);
            try std.testing.expectEqualSlices(np.Pt, a.pin_xy[a.dev_pin0[i]..a.dev_pin0[i + 1]], b.pin_xy[b.dev_pin0[j]..b.dev_pin0[j + 1]]);
        }
        try support.expectConnected(&a, lib);
        try support.expectConnected(&b, lib);
        try std.testing.expectEqual(0, try support.shorts(gpa, &a, true));
        try std.testing.expectEqual(0, try support.shorts(gpa, &b, true));
    }
}

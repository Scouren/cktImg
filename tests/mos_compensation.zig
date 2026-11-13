//! Compensation decks → placed MOS channels beside amplifier inputs.
//! Oracle: AnalogGenie ag-782's independently drawn M7/M8 D/S coordinates.
//! Named input ports describe connectivity even when the block has no glyph.
//!
//! Contents: private pin lookup, then public placement regressions.

const std = @import("std");
const np = @import("NetlistParser");
const support = @import("support.zig");
const testing = std.testing;

const models = "Input compensation\n.model nch nmos\n.model qnpn npn\n";
const stage = "I1 VDD net2 DC 1m\nI2 VDD net3 DC 1m\n" ++
    "M1 net0 va- VSS VSS nch\nM2 net4 va+ VSS VSS nch\n" ++
    "M3 net0 vb- VSS VSS nch\nM4 net4 vb+ VSS VSS nch\n" ++
    "Q5 net2 VB net0 VSS qnpn\nQ6 net3 VB net4 VSS qnpn\n";
const switches = "M7 net5 VN net3 VSS nch\nM8 net1 VN net2 VSS nch\n";
const capacitors = "C1 vo+ net5 1p\nC2 vo- net1 1p\n";
const amplifier = ".subckt opamp_differential VDD VSS VIP VIN VOP VON params: gain=1e6 vocm=0\n" ++
    "VCM ncm 0 DC {vocm}\nEPLUS VOP ncm VIP VIN {gain/2}\nEMINUS VON ncm VIN VIP {gain/2}\n" ++
    ".ends opamp_differential\n";
const instance = "X1 VDD VSS net2 net3 vo+ vo- opamp_differential gain=1e6\n";

// ---- private ----

fn pin(p: *const np.Placed, name: []const u8, k: u32) np.Pt {
    const d = np.checks.deviceIn(p, name).?;
    return p.pin_xy[p.pinRange(d)[0] + k];
}

test "compensation: a capacitor leaf to a named amplifier input keeps its MOS channel flat" {
    // Oracle: source ag-782 M7/M8 are horizontal. Reordering block ports,
    // renaming its family and cards, and reversing channels preserve this
    // decision. The second block has semantic inputs but no known glyph.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const cases = [_]struct { deck: []const u8, names: [2][]const u8 }{
        .{ .deck = models ++ amplifier ++ stage ++ switches ++ capacitors ++ instance, .names = .{ "m7", "m8" } },
        .{ .deck = models ++ ".subckt custom_stage VON VIN VSS VOP VIP VDD\n.ends\n" ++
            "Xrenamed vo- net3 VSS vo+ net2 VDD custom_stage\n" ++ capacitors ++
            "M80 net2 VN net1 VSS nch\nM70 net3 VN net5 VSS nch\n" ++ stage, .names = .{ "m70", "m80" } },
    };
    for (cases) |case| for ([_]bool{ false, true }) |compact| {
        var p = try np.place(testing.allocator, &.{ .layout = .{ .compact = compact } }, lib, &.{case.deck}, null);
        defer p.deinit();
        for (case.names) |name| {
            try testing.expectEqual(pin(&p, name, 0).y, pin(&p, name, 2).y);
            try testing.expect(pin(&p, name, 0).x != pin(&p, name, 2).x);
        }
        for ([_][]const u8{ "q5", "q6" }) |name| {
            try testing.expectEqual(pin(&p, name, 0).x, pin(&p, name, 2).x);
            try testing.expect(pin(&p, name, 0).y != pin(&p, name, 2).y);
        }
        try support.expectConnected(&p, lib);
        try testing.expectEqual(0, try support.shorts(testing.allocator, &p, true));
    };
}

test "compensation: unknown block ports and terminal capacitances give no horizontal evidence" {
    // Oracle: the declared port contract supplies input identity, not X's
    // position on the card. Own gate/channel capacitance is not a series
    // signal capacitor; these are ablations of the source example.
    const lib = try support.library(testing.allocator);
    defer support.freeLibrary(testing.allocator, lib);
    const decks = [_][]const u8{
        models ++ ".subckt custom_stage VDD VSS signal_a signal_b VOP VON\n.ends\n" ++
            stage ++ switches ++ capacitors ++ "X1 VDD VSS net2 net3 vo+ vo- custom_stage\n",
        models ++ amplifier ++ stage ++ switches ++ instance ++ "C1 VN net5 1p\nC2 VN net1 1p\n",
        models ++ amplifier ++ stage ++ switches ++ instance ++ "C1 net3 net5 1p\nC2 net2 net1 1p\n",
        models ++ amplifier ++ stage ++ switches ++ instance ++ "C1 net5 net5 1p\nC2 net1 net1 1p\n",
        models ++ amplifier ++ stage ++ switches ++ capacitors ++ instance ++ "*@ upright m7 m8\n",
    };
    for (decks) |deck| {
        var p = try np.place(testing.allocator, &.default, lib, &.{deck}, null);
        defer p.deinit();
        for ([_][]const u8{ "m7", "m8" }) |name| {
            try testing.expectEqual(pin(&p, name, 0).x, pin(&p, name, 2).x);
            try testing.expect(pin(&p, name, 0).y != pin(&p, name, 2).y);
        }
        try support.expectConnected(&p, lib);
    }
}

//! Exact unsigned reference contracts -> glyph, port and caller checks.
//! Cites docs/research/reference-amplifiers.md and its actual SVG lead audit.
//! Imported by tests/schemify.zig with NetlistParser and cktimg.
//!
//! Contents: private ink helpers, then source, boundary and precedence tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const cktimg = @import("cktimg");

const Case = struct {
    source: []const u8,
    family: []const u8,
    ports: []const u8,
    sides: []const u8,
    bindings: []const u8 = "",
};

const source_cases = [_]Case{
    .{ .source = "ag-2415:x1", .family = "aea", .ports = "vdd vss vref out", .sides = "UDLR", .bindings = "vdd vss vref net4" },
    .{ .source = "ag-2420:x1", .family = "erroramp", .ports = "vdd vss vref out", .sides = "UDLR", .bindings = "vdd vss vref veaout" },
    .{ .source = "ag-2421:x1", .family = "aea", .ports = "vdd vss vref vbn out", .sides = "UDLDR", .bindings = "vdd vss vref net0 net5" },
    .{ .source = "ag-2422:x1", .family = "error_amp", .ports = "vdd vss vref vbn out", .sides = "UDLDR", .bindings = "vdd vss vref net3 vea" },
    .{ .source = "ag-2425:x1", .family = "aea", .ports = "vdd vss vref out", .sides = "UDLR", .bindings = "vdd vss vref veaout" },
    .{ .source = "ag-2427:x1", .family = "error_amplifier", .ports = "vss vref vea", .sides = "DLR", .bindings = "vss vref vea" },
    .{ .source = "ag-2428:x1", .family = "aea", .ports = "vdd vss vref out vb1", .sides = "UDLRD", .bindings = "vdd vss vref veaout vb1" },
    .{ .source = "ag-2434:x1", .family = "aea", .ports = "vdd vss vref out", .sides = "UDLR", .bindings = "vdd vss vref net2" },
    .{ .source = "ag-2435:x1", .family = "aea", .ports = "vdd vss vref out", .sides = "UDLR", .bindings = "vdd vss vref veaout" },
    .{ .source = "ag-2436:x1", .family = "error_amp", .ports = "vdd vss vref nb out", .sides = "UDLDR", .bindings = "vdd vss vref net0 net4" },
    .{ .source = "ag-2440:x2", .family = "aea", .ports = "vdd vss vref vbn out", .sides = "UDLDR", .bindings = "vdd vss vref vbn net3" },
    .{ .source = "ag-2441:x1", .family = "aea", .ports = "vdd vss vref out vbn", .sides = "UDLRD", .bindings = "vdd vss vref net2 net0" },
    .{ .source = "ag-2443:x1", .family = "aea", .ports = "vdd vss vref nb out", .sides = "UDLDR", .bindings = "vdd vss vref net0 vea" },
    .{ .source = "ag-2444:x2", .family = "aea", .ports = "vdd vss vref vbn out", .sides = "UDLDR", .bindings = "vdd vss vref net3 net2" },
    .{ .source = "ag-2447:x1", .family = "aea", .ports = "vdd vss vref vbn out", .sides = "UDLDR", .bindings = "vdd vss vref net3 net5" },
};

// ---- private ----

fn outline(c: np.Class, vertices: usize) ?[]const np.Pt {
    var found: ?[]const np.Pt = null;
    for (c.draw) |op| if (op == .polyline) {
        const ps = op.polyline;
        if (ps.len != vertices + 1 or !ps[0].eql(ps[vertices])) continue;
        if (found != null) return null;
        found = ps[0..vertices];
    };
    return found;
}

fn inside(p: np.Pt, triangle: []const np.Pt) bool {
    std.debug.assert(triangle.len == 3);
    var positive = true;
    var negative = true;
    for (triangle, 0..) |a, i| {
        const b = triangle[(i + 1) % 3];
        const cross = (@as(i64, b.x) - a.x) * (@as(i64, p.y) - a.y) -
            (@as(i64, b.y) - a.y) * (@as(i64, p.x) - a.x);
        positive = positive and cross > 0;
        negative = negative and cross < 0;
    }
    return positive or negative;
}

fn edgeSide(a: np.Pt, b: np.Pt, p: np.Pt) i64 {
    return (@as(i64, b.x) - a.x) * (@as(i64, p.y) - a.y) -
        (@as(i64, b.y) - a.y) * (@as(i64, p.x) - a.x);
}

fn outward(c: np.Class, pin: usize, attachment: np.Pt, body: []const np.Pt) bool {
    const terminal = c.terminals[pin].at;
    const directed = switch (c.side(pin, .r0) orelse return false) {
        .left => terminal.y == attachment.y and terminal.x < attachment.x,
        .right => terminal.y == attachment.y and terminal.x > attachment.x,
        .up => terminal.x == attachment.x and terminal.y < attachment.y,
        .down => terminal.x == attachment.x and terminal.y > attachment.y,
    };
    if (!directed) return false;
    for (body, 0..) |a, i| {
        const b = body[(i + 1) % 3];
        if (edgeSide(a, b, attachment) != 0 or
            attachment.x < @min(a.x, b.x) or attachment.x > @max(a.x, b.x) or
            attachment.y < @min(a.y, b.y) or attachment.y > @max(a.y, b.y)) continue;
        const inner = edgeSide(a, b, body[(i + 2) % 3]);
        const outer = edgeSide(a, b, terminal);
        if ((inner > 0 and outer < 0) or (inner < 0 and outer > 0)) return true;
    }
    return false;
}

fn ownLead(c: np.Class, body: []const np.Pt, a: np.Pt, b: np.Pt) ?usize {
    var found: ?usize = null;
    for (c.terminals, 0..) |terminal, i| {
        const attachment = if (terminal.at.eql(a)) b else if (terminal.at.eql(b)) a else continue;
        if (found != null or !outward(c, i, attachment, body)) return null;
        found = i;
    }
    return found;
}

fn leadCertificate(c: np.Class) bool {
    const body = outline(c, 3) orelse return false;
    for (c.draw) |op| if (op == .line) {
        if (ownLead(c, body, op.line.a, op.line.b) == null) return false;
    };
    for (c.terminals, 0..) |_, i| {
        var count: usize = 0;
        for (c.draw) |op| if (op == .line) {
            count += @intFromBool(ownLead(c, body, op.line.a, op.line.b) == i);
        };
        if (count != 1) return false;
    }
    return c.terminals.len != 0;
}

fn unsignedTriangle(c: np.Class) !void {
    const body = outline(c, 3) orelse return error.MissingTriangle;
    try testing.expect(outline(c, 4) == null);
    const area = (@as(i64, body[1].x) - body[0].x) * (@as(i64, body[2].y) - body[0].y) -
        (@as(i64, body[1].y) - body[0].y) * (@as(i64, body[2].x) - body[0].x);
    try testing.expect(area != 0);
    var plus: usize = 0;
    var minus: usize = 0;
    for (c.draw) |op| switch (op) {
        .text => |t| {
            plus += @intFromBool(std.mem.eql(u8, t.s, "+"));
            minus += @intFromBool(std.mem.eql(u8, t.s, "-"));
        },
        .line => |line| try testing.expect(!(inside(line.a, body) and inside(line.b, body))),
        .polyline => |ps| {
            const interior = for (ps) |p| {
                if (!inside(p, body)) break false;
            } else true;
            try testing.expect(!interior);
        },
        else => {},
    };
    // Named source oracles: plus-none and minus-none. VREF is unsigned;
    // a plain triangle does not imply a fabricated second signed input.
    try testing.expectEqual(@as(usize, 0), plus);
    try testing.expectEqual(@as(usize, 0), minus);
    try testing.expect(leadCertificate(c));
}

fn sourceCase(row: Case) !void {
    errdefer std.debug.print("unsigned reference contract: {s}\n", .{row.source});
    const text = try std.fmt.allocPrint(testing.allocator, "reference glyph\n.subckt {s} {s}\n.ends\n", .{ row.family, row.ports });
    defer testing.allocator.free(text);
    var nl = try np.netlist.parse(testing.allocator, &.{text}, null);
    defer nl.deinit(testing.allocator);
    var lib = np.Library.init(testing.allocator);
    defer lib.deinit();
    const def = &nl.defs[0];
    const c = lib.at(try lib.blockFor(def));
    try unsignedTriangle(c);
    try testing.expectEqual(def.ports.len, c.terminals.len);
    try testing.expectEqual(row.sides.len, c.terminals.len);
    var input: ?np.Pt = null;
    var output: ?np.Pt = null;
    for (def.ports, c.terminals, row.sides, 0..) |name, terminal, side, i| {
        const expected: np.Side = switch (side) {
            'U' => .up,
            'D' => .down,
            'L' => .left,
            'R' => .right,
            else => unreachable,
        };
        try testing.expectEqualStrings(name, terminal.name);
        try testing.expectEqual(expected, c.side(i, .r0).?);
        try testing.expect(!terminal.hidden and !terminal.ground_ref);
        for (c.terminals[i + 1 ..]) |other| try testing.expect(!terminal.at.eql(other.at));
        if (side == 'L') {
            try testing.expect(input == null);
            try testing.expectEqualStrings("vref", name);
            input = terminal.at;
        }
        if (side == 'R') {
            try testing.expect(output == null);
            try testing.expect(std.mem.eql(u8, name, "out") or std.mem.eql(u8, name, "vea"));
            output = terminal.at;
        }
    }
    try testing.expect(input != null and output != null);
    try testing.expect(input.?.x < output.?.x);
    try testing.expectEqual(input.?.y, output.?.y);
    const body = outline(c, 3).?;
    var apex: usize = 0;
    var base: usize = 0;
    for (body) |p| {
        apex += @intFromBool(p.y == output.?.y and p.x > input.?.x and p.x < output.?.x);
        base += @intFromBool(p.x > input.?.x and p.x < 0);
    }
    try testing.expectEqual(@as(usize, 1), apex);
    try testing.expectEqual(@as(usize, 2), base);
}

fn onWire(w: cktimg.layout.Seg, p: cktimg.layout.P) bool {
    return (w[0] == w[2] and p[0] == w[0] and p[1] >= @min(w[1], w[3]) and p[1] <= @max(w[1], w[3])) or
        (w[1] == w[3] and p[1] == w[1] and p[0] >= @min(w[0], w[2]) and p[0] <= @max(w[0], w[2]));
}

fn binding(a: std.mem.Allocator, deck: *const cktimg.spice.Deck, drawn: cktimg.layout.Drawn, at: cktimg.layout.P, want: []const u8) !void {
    // Independent physical component: only endpoint/T/overlap joins, never
    // label identity or a proper crossing. Every reached marker must name
    // this literal X-card binding; a swapped port cannot pass by proximity.
    const wires = drawn.wire.items;
    const seen = try a.alloc(bool, wires.len);
    for (wires, seen) |w, *v| v.* = onWire(w, at);
    for (0..wires.len) |_| {
        var changed = false;
        for (wires, 0..) |w, i| {
            if (!seen[i]) continue;
            for (wires, 0..) |v, j| {
                if (seen[j] or !(onWire(w, .{ v[0], v[1] }) or onWire(w, .{ v[2], v[3] }) or
                    onWire(v, .{ w[0], w[1] }) or onWire(v, .{ w[2], w[3] }))) continue;
                seen[j] = true;
                changed = true;
            }
        }
        if (!changed) break;
    }
    var named = false;
    for (drawn.mark.items) |mark| {
        const reached = std.mem.eql(i32, &at, &mark.at) or for (wires, seen) |w, visited| {
            if (visited and onWire(w, mark.at)) break true;
        } else false;
        if (!reached) continue;
        if (!std.mem.eql(u8, want, deck.netKey(0, mark.net))) return error.WrongBinding;
        named = true;
    }
    if (!named) return error.UnnamedBinding;
}

test "reference amplifiers: all 15 source contracts retain unsigned input and apex output" {
    // Oracle: 15 actual triangles, 53 named visible lead certificates and
    // zero source polarity strokes. Source VSS is absent; all 68 declared
    // ports remain electrical pins in the generated canonical symbol.
    // Side strings are canonical API choices. AG2421's supply points down
    // and bias up; AG2444's supply ends right and bias up. Those source
    // exceptions are not universal placement or rotation requirements.
    for (source_cases) |row| try sourceCase(row);
}

test "reference amplifiers: case, declaration order and absent rails preserve named roles" {
    // Oracle: a port permutation changes neither electrical identity nor
    // role; absent optional rails cannot synthesize extra terminals.
    try sourceCase(.{ .source = "permuted ag-2421", .family = "aEa", .ports = "OUT VBN VREF VSS VDD", .sides = "RDLDU" });
    try sourceCase(.{ .source = "permuted ag-2420", .family = "ErrorAmp", .ports = "VREF OUT VSS VDD", .sides = "LRDU" });
    try sourceCase(.{ .source = "permuted ag-2427", .family = "ERROR_AMPLIFIER", .ports = "VEA VREF VSS", .sides = "RLD" });
    try sourceCase(.{ .source = "permuted ag-2436", .family = "Error_Amp", .ports = "NB OUT VDD VREF VSS", .sides = "DRULD" });
    try sourceCase(.{ .source = "policy: no rails", .family = "AEA", .ports = "VREF VEA", .sides = "LR" });
    try sourceCase(.{ .source = "policy: supply only", .family = "ERRORAMP", .ports = "VREF VDD OUT VB1", .sides = "LURD" });
}

test "reference amplifiers: literal own-body leads reject missing, detached and inward strokes" {
    // Oracle: a literal triangle and independently chosen boundary points;
    // neither Library nor the generated glyph chooses these coordinates.
    const terms = [_]np.library.Terminal{
        .{ .name = "vdd", .at = .{ .x = 0, .y = -30 }, .side = .up },
        .{ .name = "vss", .at = .{ .x = -10, .y = 30 }, .side = .down },
        .{ .name = "vref", .at = .{ .x = -40, .y = 0 }, .side = .left },
        .{ .name = "out", .at = .{ .x = 40, .y = 0 }, .side = .right },
    };
    const draw = [_]np.library.DrawOp{
        .{ .polyline = &.{ .{ .x = -20, .y = -20 }, .{ .x = 20, .y = 0 }, .{ .x = -20, .y = 20 }, .{ .x = -20, .y = -20 } } },
        np.library.DrawOp.ln(0, -10, 0, -30),
        np.library.DrawOp.ln(-10, 15, -10, 30),
        np.library.DrawOp.ln(-20, 0, -40, 0),
        np.library.DrawOp.ln(20, 0, 40, 0),
    };
    const good: np.Class = .{ .name = "literal-reference", .terminals = &terms, .draw = &draw };
    try testing.expect(leadCertificate(good));
    var changed = good;
    changed.draw = draw[0..1];
    try testing.expect(!leadCertificate(changed)); // All leads removed.
    for (1..draw.len) |removed| {
        var missing: [draw.len - 1]np.library.DrawOp = undefined;
        var n: usize = 0;
        for (draw, 0..) |op, i| if (i != removed) {
            missing[n] = op;
            n += 1;
        };
        changed.draw = &missing;
        try testing.expect(!leadCertificate(changed));
    }
    var shifted = draw;
    shifted[3] = np.library.DrawOp.ln(-19, 0, -40, 0); // Attaches inside, not to an edge.
    changed.draw = &shifted;
    try testing.expect(!leadCertificate(changed));
    shifted[3] = np.library.DrawOp.ln(-20, 1, -40, 0); // Diagonal instead of outward.
    try testing.expect(!leadCertificate(changed));
    shifted[3] = np.library.DrawOp.ln(20, 0, -40, 0); // Crosses the body from the far apex.
    try testing.expect(!leadCertificate(changed));
    const duplicate = draw ++ [_]np.library.DrawOp{draw[3]};
    changed.draw = &duplicate;
    try testing.expect(!leadCertificate(changed));
    const orphan = draw ++ [_]np.library.DrawOp{np.library.DrawOp.ln(70, 70, 80, 70)};
    changed.draw = &orphan;
    try testing.expect(!leadCertificate(changed));
}

test "reference amplifiers: VB1 VBN and NB preserve role-keyed canonical geometry" {
    // Oracle: spelling substitution for one declared bias role. This is
    // canonical alias policy; source VSS has no measured position.
    for ([_][]const u8{ "AEA", "ERRORAMP", "ERROR_AMP", "ERROR_AMPLIFIER" }) |family| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var baseline: ?np.Class = null;
        for ([_][]const u8{ "VB1", "VBN", "NB" }) |bias| {
            const text = try std.fmt.allocPrint(a, "bias alias\n.subckt {s} VDD VSS VREF OUT {s}\n.ends\n", .{ family, bias });
            // Keep all three classes alive for the role comparison.
            const nl = try np.netlist.parse(a, &.{text}, null);
            var lib = np.Library.init(a);
            const c = lib.at(try lib.blockFor(&nl.defs[0]));
            try unsignedTriangle(c);
            try testing.expectEqual(@as(usize, 5), c.terminals.len);
            try testing.expect(std.ascii.eqlIgnoreCase(bias, c.terminals[4].name));
            if (baseline) |old| {
                try testing.expectEqualDeep(old.draw, c.draw);
                for (old.terminals, c.terminals, 0..) |before, after, i| {
                    if (i != 4) try testing.expectEqualStrings(before.name, after.name);
                    try testing.expectEqualDeep(before.at, after.at);
                    try testing.expectEqual(before.side, after.side);
                    try testing.expectEqual(before.hidden, after.hidden);
                    try testing.expectEqual(before.ground_ref, after.ground_ref);
                }
            } else baseline = c;
        }
    }
}

test "reference amplifiers: exact families and complete roles leave near misses boxed" {
    // Oracle: ERRAMP AG2442 is an actual rectangle with familiar ports.
    // The other source exclusions retain unknown/mixed roles; synthetic
    // mutations prove the bounded contract without guessing their shapes.
    const cases = [_]struct { family: []const u8, ports: []const u8 }{
        .{ .family = "ERRAMP", .ports = "VDD VSS VREF VBN OUT" },
        .{ .family = "EA1", .ports = "VDD VSS VFP1 VREF VX2 VB1 VISR VX1" },
        .{ .family = "AEA", .ports = "VDD VSS VREF INP OUT VX" },
        .{ .family = "AEA", .ports = "VDD VSS VREF OUT IB" },
        .{ .family = "AEA", .ports = "VDD VSS VREF OUT VBT" },
        .{ .family = "AEA2", .ports = "VDD VSS VREF OUT" },
        .{ .family = "my_aea", .ports = "VDD VSS VREF OUT" },
        .{ .family = "error_amp_extra", .ports = "VDD VSS VREF OUT" },
        .{ .family = "ERRORAMP", .ports = "VDD VSS VREF OUT VEA" },
        .{ .family = "ERROR_AMP", .ports = "VDD VSS VREF OUT VB1 VBN" },
        .{ .family = "ERROR_AMP", .ports = "VDD VSS VREF OUT VBN NB" },
        .{ .family = "ERROR_AMPLIFIER", .ports = "VDD VSS VREF OUT VB1 NB" },
        .{ .family = "AEA", .ports = "VDD VSS VREF OUT INN" },
        .{ .family = "AEA", .ports = "VDD VSS VREF OUT IN" },
        .{ .family = "AEA", .ports = "VDD VSS VREF OUT ENABLE" },
        .{ .family = "AEA", .ports = "VDD VSS VREF OUT VB2" },
        .{ .family = "ERRORAMP", .ports = "VDD VSS OUT" },
        .{ .family = "ERROR_AMP", .ports = "VDD VSS VREF VB1" },
        .{ .family = "ERROR_AMPLIFIER", .ports = "VCC VSS VREF OUT" },
        .{ .family = "OPAMP", .ports = "VDD VSS VREF OUT" },
        .{ .family = "AMP", .ports = "VDD VSS INN VEA" },
        .{ .family = "COMP", .ports = "VDD VSS INN OUT VBN" },
        .{ .family = "AEA", .ports = "VDD VSS INN VEA" },
        .{ .family = "AEA", .ports = "VDD VSS INN OUT NB" },
    };
    for (cases) |row| {
        errdefer std.debug.print("reference near miss: {s} {s}\n", .{ row.family, row.ports });
        const text = try std.fmt.allocPrint(testing.allocator, "bounded reference\n.subckt {s} {s}\n.ends\n", .{ row.family, row.ports });
        defer testing.allocator.free(text);
        var nl = try np.netlist.parse(testing.allocator, &.{text}, null);
        defer nl.deinit(testing.allocator);
        try testing.expectEqual(.box, np.block_symbols.identify(row.family, nl.defs[0].ports));
        var lib = np.Library.init(testing.allocator);
        defer lib.deinit();
        const c = lib.at(try lib.blockFor(&nl.defs[0]));
        try testing.expect(outline(c, 4) != null and outline(c, 3) == null);
        try testing.expectEqual(nl.defs[0].ports.len, c.terminals.len);
        for (nl.defs[0].ports, c.terminals) |name, pin| {
            try testing.expectEqualStrings(name, pin.name);
            try testing.expect(!pin.hidden);
        }
    }
    // Exact duplicate declarations are checked at the glyph boundary,
    // independently of whether a SPICE parser admits repeated port names.
    try testing.expectEqual(.box, np.block_symbols.identify("AEA", &.{ "VREF", "vref", "OUT" }));
    try testing.expectEqual(.box, np.block_symbols.identify("ERRORAMP", &.{ "VDD", "vdd", "VREF", "OUT" }));
    try testing.expectEqual(.box, np.block_symbols.identify("ERROR_AMP", &.{ "VSS", "vss", "VREF", "OUT" }));
}

test "reference amplifiers: caller classes and explicit sides retain precedence" {
    // Oracle: public Library ownership. Source-derived defaults cannot
    // replace registered terminals or an explicitly directed reference.
    for ([_][]const u8{ "AEA", "ERRORAMP", "ERROR_AMP", "ERROR_AMPLIFIER" }) |family| {
        const text = try std.fmt.allocPrint(testing.allocator, "caller reference\n.subckt {s} VDD VSS VREF VBN OUT\n*@ right VREF\n.ends\n", .{family});
        defer testing.allocator.free(text);
        var nl = try np.netlist.parse(testing.allocator, &.{text}, null);
        defer nl.deinit(testing.allocator);
        var lib = np.Library.init(testing.allocator);
        defer lib.deinit();
        const def = &nl.defs[0];
        const c = lib.at(try lib.blockFor(def));
        // The triangle, mirrored to put VREF on the right (library.3).
        try testing.expect(outline(c, 3) != null);
        try testing.expectEqual(np.Side.right, c.side(2, .r0).?);
        const terms = try testing.allocator.dupe(np.library.Terminal, c.terminals);
        defer testing.allocator.free(terms);
        terms[2].at = .{ .x = 83, .y = -17 };
        terms[2].side = .right;
        var own = np.Library.init(testing.allocator);
        defer own.deinit();
        const custom = try own.register(.{ .name = def.name, .terminals = terms, .draw = &.{np.library.DrawOp.ln(-11, 9, 17, -13)} });
        try testing.expectEqual(custom, try own.blockFor(def));
        const retained = own.at(custom);
        try testing.expectEqual(@as(usize, 1), retained.draw.len);
        for (terms, retained.terminals) |expected, actual| try testing.expectEqualDeep(expected, actual);
    }
}

test "reference amplifiers: PININFO preserves declared directions through Schemify" {
    // Oracle: explicit I/O/B metadata outranks inferred glyph roles.
    // Matching metadata admits a triangle; conflicting metadata retains a
    // box with those exact directions, including a caller-directed bias.
    const cases = [_]struct { info: []const u8, dirs: []const u8, triangle: bool }{
        .{ .info = "VDD:B VSS:B VREF:I VBN:B OUT:O", .dirs = "BBIBO", .triangle = true },
        .{ .info = "VDD:B VSS:B VREF:O VBN:B OUT:I", .dirs = "BBOBI", .triangle = false },
        .{ .info = "VDD:B VSS:B VREF:I VBN:O OUT:O", .dirs = "BBIOO", .triangle = false },
    };
    for ([_][]const u8{ "AEA", "ERRORAMP", "ERROR_AMP", "ERROR_AMPLIFIER" }) |family| {
        for (cases) |row| {
            var arena = std.heap.ArenaAllocator.init(testing.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            const text = try std.fmt.allocPrint(a, "* reference directions\n.subckt {s} VDD VSS VREF VBN OUT\n*.PININFO {s}\nR1 VDD VSS 1meg\n.ends\nX1 vdd 0 reference bias result {s}\n", .{ family, row.info, family });
            var c = try cktimg.Converter.init(testing.allocator, a, "reference.sp", text);
            defer c.deinit();
            const cell = c.deck.findCell(family).?;
            const sym = cktimg.recognize.subSymbol(cell);
            const pins = c.rec.syms.pins(sym);
            const names = [_][]const u8{ "vdd", "vss", "vref", "vbn", "out" };
            try testing.expectEqual(names.len, pins.len);
            for (names, pins, row.dirs) |name, pin, dir| {
                try testing.expect(std.ascii.eqlIgnoreCase(name, pin.name));
                const expected: cktimg.spice.Dir = switch (dir) {
                    'I' => .in,
                    'O' => .out,
                    'B' => .inout,
                    else => unreachable,
                };
                try testing.expectEqual(expected, pin.dir);
            }
            const class_name = try std.fmt.allocPrint(a, "b{d}", .{sym});
            const glyph = c.lib.at(c.lib.find(class_name).?);
            if (row.triangle) {
                try unsignedTriangle(glyph);
            } else try testing.expect(outline(glyph, 4) != null and outline(glyph, 3) == null);
        }
    }
}

test "reference amplifiers: plain source calls preserve emitted directions and actual terminal bindings" {
    // Oracle: literal source declarations/calls, independently audited SVG
    // unsigned triangles, and Schemify's pin/marker records. No PININFO is
    // injected: generic fallback calls VREF an output, so this detects the
    // actual admission and metadata boundary rather than reparsing a deck.
    for (source_cases) |row| {
        errdefer std.debug.print("plain reference call: {s}\n", .{row.source});
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const instance = row.source[std.mem.indexOfScalar(u8, row.source, ':').? + 1 ..];
        // A reduced one-X deck otherwise leaves each unused singleton as
        // a legitimate no-connect. Saving each literal node requires its
        // real name without changing the declaration, call or PININFO.
        var saved: std.ArrayList(u8) = .empty;
        var requested = std.mem.tokenizeScalar(u8, row.bindings, ' ');
        while (requested.next()) |net| try saved.print(a, " v({s})", .{net});
        const text = try std.fmt.allocPrint(a, "* plain source contract\n.subckt {s} {s}\n.ends\n{s} {s} {s}\n.save{s}\n", .{ row.family, row.ports, instance, row.bindings, row.family, saved.items });
        var c = try cktimg.Converter.init(testing.allocator, a, "reference.sp", text);
        defer c.deinit();
        try testing.expectEqual(@as(usize, 0), c.deck.pininfo.len);
        const cell = c.deck.findCell(row.family).?;
        const sym = cktimg.recognize.subSymbol(cell);
        try c.step(); // Emits the actual component before its calling bench.
        const emitted = (try cktimg.place.libCell(a, "", row.family, c.out.files.items[0].bytes)).?;
        try testing.expectEqual(row.sides.len, emitted.pins.len);
        var names = std.mem.tokenizeScalar(u8, row.ports, ' ');
        for (emitted.pins, row.sides) |pin, side| {
            try testing.expectEqualStrings(names.next().?, pin.name);
            const dir: cktimg.spice.Dir = switch (side) {
                'L' => .in,
                'R' => .out,
                'U', 'D' => .inout,
                else => unreachable,
            };
            try testing.expectEqual(dir, pin.dir);
        }
        try testing.expect(names.next() == null);
        const class_name = try std.fmt.allocPrint(a, "b{d}", .{sym});
        const glyph = c.lib.at(c.lib.find(class_name).?);
        try unsignedTriangle(glyph);
        const drawn = try cktimg.layout.draw(testing.allocator, a, &c.lib, &c.deck, &c.rec, 0, &c.budget);
        try testing.expect(drawn.fallback == null and drawn.strays == 0);
        try testing.expectEqual(@as(usize, 1), drawn.x.items.len);
        const ori = drawn.orient.items[0];
        const transform: np.Orient = .{ .rot = @intCast(ori & 3), .mirror = ori >= 4 };
        var nets = std.mem.tokenizeScalar(u8, row.bindings, ' ');
        for (emitted.pins, glyph.terminals) |pin, terminal| {
            try testing.expectEqualStrings(pin.name, terminal.name);
            try testing.expectEqualDeep(np.Pt{ .x = pin.x, .y = pin.y }, terminal.at);
            const p = transform.apply(.{ .x = pin.x, .y = pin.y });
            const at: cktimg.layout.P = .{ drawn.x.items[0] + p.x, drawn.y.items[0] + p.y };
            const expected = nets.next().?;
            errdefer std.debug.print("binding {s}.{s} expected {s} at {any}\n", .{ row.source, pin.name, expected, at });
            try binding(a, &c.deck, drawn, at, expected);
        }
        try testing.expect(nets.next() == null);
    }
}

test "reference amplifiers: literal binding oracle rejects wrong names and detached ink" {
    // Literal geometry/expected names; no glyph or parser chooses the path.
    // A terminal label is electrical, while a detached same-name label and
    // a proper crossing are not substitutes for a connecting segment.
    const cases = [_]struct { name: []const u8, wires: []const cktimg.layout.Seg, marks: []const cktimg.layout.Mark, want: []const u8 = "rightnet", err: ?anyerror = null }{
        .{ .name = "direct terminal label", .wires = &.{}, .marks = &.{.{ .at = .{ 0, 0 }, .net = 0, .orient = 0 }} },
        .{ .name = "connected two segment", .wires = &.{ .{ 0, 0, 10, 0 }, .{ 10, 0, 10, 10 } }, .marks = &.{.{ .at = .{ 10, 10 }, .net = 0, .orient = 0 }} },
        .{ .name = "reversed segment", .wires = &.{ .{ 10, 0, 0, 0 }, .{ 10, 10, 10, 0 } }, .marks = &.{.{ .at = .{ 10, 10 }, .net = 0, .orient = 0 }} },
        .{ .name = "endpoint T join", .wires = &.{ .{ 0, 0, 20, 0 }, .{ 10, 0, 10, 10 } }, .marks = &.{.{ .at = .{ 10, 10 }, .net = 0, .orient = 0 }} },
        .{ .name = "collinear overlap", .wires = &.{ .{ 0, 0, 10, 0 }, .{ 5, 0, 20, 0 } }, .marks = &.{.{ .at = .{ 20, 0 }, .net = 0, .orient = 0 }} },
        .{ .name = "foreign proper crossing stays separate", .wires = &.{ .{ 0, 0, 20, 0 }, .{ 10, -10, 10, 10 } }, .marks = &.{ .{ .at = .{ 20, 0 }, .net = 0, .orient = 0 }, .{ .at = .{ 10, 10 }, .net = 1, .orient = 0 } } },
        .{ .name = "wrong expected binding", .wires = &.{.{ 0, 0, 10, 0 }}, .marks = &.{.{ .at = .{ 10, 0 }, .net = 0, .orient = 0 }}, .want = "wrongnet", .err = error.WrongBinding },
        .{ .name = "wrong net marker", .wires = &.{.{ 0, 0, 10, 0 }}, .marks = &.{.{ .at = .{ 10, 0 }, .net = 1, .orient = 0 }}, .err = error.WrongBinding },
        .{ .name = "wrong and right markers cannot hide short", .wires = &.{.{ 0, 0, 10, 0 }}, .marks = &.{ .{ .at = .{ 10, 0 }, .net = 0, .orient = 0 }, .{ .at = .{ 5, 0 }, .net = 1, .orient = 0 } }, .err = error.WrongBinding },
        .{ .name = "one unit gap", .wires = &.{ .{ 0, 0, 10, 0 }, .{ 11, 0, 20, 0 } }, .marks = &.{.{ .at = .{ 20, 0 }, .net = 0, .orient = 0 }}, .err = error.UnnamedBinding },
        .{ .name = "removed bridge", .wires = &.{.{ 10, 0, 20, 0 }}, .marks = &.{.{ .at = .{ 20, 0 }, .net = 0, .orient = 0 }}, .err = error.UnnamedBinding },
        .{ .name = "proper crossing cannot substitute bridge", .wires = &.{ .{ 0, 0, 20, 0 }, .{ 10, -10, 10, 10 } }, .marks = &.{.{ .at = .{ 10, 10 }, .net = 0, .orient = 0 }}, .err = error.UnnamedBinding },
    };
    for (cases) |row| {
        errdefer std.debug.print("binding oracle mutation: {s}\n", .{row.name});
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const deck = try cktimg.spice.parse(a, "* literal names\nR1 rightnet wrongnet 1k\n");
        try testing.expectEqualStrings("rightnet", deck.netKey(0, 0));
        try testing.expectEqualStrings("wrongnet", deck.netKey(0, 1));
        var drawn: cktimg.layout.Drawn = .{};
        try drawn.wire.appendSlice(a, row.wires);
        try drawn.mark.appendSlice(a, row.marks);
        if (row.err) |err| try testing.expectError(err, binding(a, &deck, drawn, .{ 0, 0 }, row.want)) else try binding(a, &deck, drawn, .{ 0, 0 }, row.want);
    }
}

//! The schematic a layout fills (docs/ALGORITHM.md): each device as its
//! library class, the drawing's nodes (devices, terminal symbols, labels)
//! and pins, and its wires. Stage 1, the nets' roles (R1–R3), is here; the
//! stages that place and wire are `structure.zig`, `skeleton.zig` and
//! `sketch.zig`, and `placed.zig` exports the result.
//!
//! Human Rules:
//! - schematic.1 (habit) A net named `vdd…`, `vcc…`, `avdd…`, `dvdd…`,
//!   `vpp…` or `v+` is a supply, drawn with a supply symbol (R1). People:
//!   rail symbols and no port on 4,010 of the 4,157 nets so named in 5,263
//!   hand-drawn schematics, a numbered one (`vdd1`, `vcc2`) in 22 of 22.
//!   `roleFromName`
//! - schematic.2 (habit) Net 0, and a net named `gnd…`, `vss…`, `vee…`,
//!   `agnd…`, `dgnd…` or `v-`, is a ground, drawn with a ground symbol
//!   (R1). People: rail symbols and no port on 5,467 of the 5,535 nets so
//!   named, a numbered one (`vss1`, `vee2`) in 10 of 10. `guessRoles`
//! - schematic.3 (habit) A net named `vb…` or `bias…` is a bias line,
//!   drawn as a port with its name (R1). People: a port on 2,926 of the
//!   3,241 such nets with no transistor's drain or collector on them, in
//!   5,263 hand-drawn schematics. `roleFromName`
//!   Wider than people draw: a bias line a drain or collector makes is a
//!   port here too, where of 1,138 such nets 834 carry no symbol (642 are
//!   drawn in pieces joined by the written name, 192 as one wire) and 59
//!   an input port. Read as inner nets and wired, they draw 557 crossings
//!   and 1,966 corners more over 5,263 circuits: the pattern is the
//!   written name, which is the wiring's to draw (wires.13).
//! - schematic.4 (habit) A net named `vin…`, `in…` or `vref…` is an
//!   input port; one named `vout…`, `out…` or `vo` an output port (R1).
//!   People: a port and no output on 2,650 of the 2,677 nets named
//!   `vin…` or `in…` and on 580 of the 627 named `vref…` with no drain on
//!   them; a port and no input on 3,894 of the 3,935 named as an output.
//!   `roleFromName`
//! - schematic.5 (habit) A `vref…` net a transistor's drain or collector
//!   makes is an output port, not an input. People: none of the 11 such
//!   nets carries an input port (4 an output port, 6 a plain one): too
//!   few to be a rule of its own, kept for the reference a circuit makes.
//!   `guessRoles`
//! - schematic.6 (unmeasured) An unnamed net a voltage source drives from
//!   ground is an input port when the source carries a signal (`ac`,
//!   `sin`, `pulse`, `pwl`, `exp`, `sffm`, `am`, `trnoise`, `trrandom`),
//!   else a bias port, unless a `*@ driver <src> inline` line keeps the
//!   source in the circuit (R2). The hand drawings hold no bench to test
//!   it on: each is a cell (schematic.9). `guessRoles`, `isSignalSource`
//! - schematic.7 (habit) A circuit of parts (no transistor) with no pin on
//!   a ground stands on one bottom wire drawn with no ground symbol: the
//!   internal net of two pins or more that most two-pin cards end on
//!   (second pins less first pins; a voltage source's minus and the pin a
//!   current source draws from count double, a controlled source's ends
//!   as a part's), then the one with the most pins, then by name; unless
//!   a `*@ role <net> ground` line names the ground. People: 172 of 191
//!   connected pieces in 5,263 hand-drawn schematics, and that score
//!   names the wire in 77.9%; counting a controlled source's low end
//!   double as well names it in 47 of the 63 circuits that hold one,
//!   against 50. `reference`, `isReference`
//! - schematic.8 (choice) A `*@ role <net> <role>` line sets that net's
//!   role over every guess, the preferred line last: the deck's author
//!   knows what the net is. `guessRoles`
//! - schematic.9 (unmeasured) A voltage source from ground to a supply,
//!   input or bias net is not drawn in the circuit: the net's terminal
//!   symbols stand for it there, and it is drawn apart (R3). The hand
//!   drawings hold no bench to test it on; in a cell people wire such a
//!   source where it stands (1,017 of 1,018), which a `*@ driver <src>
//!   inline` line asks for. `isDriver`
//! - schematic.10 (habit) An `E` that is a dependent source, not an
//!   amplifier, is drawn as the library's two-pin `vcvs` symbol, where it
//!   has one. People: a two-pin source symbol for 37 of 37 `E` cards (464
//!   of 464 with `G`, `F` and `H`) in 5,263 hand-drawn schematics, none of
//!   which draws an `E` as an amplifier. `initDevices`
//! - schematic.11 (choice) A `*@ class <dev> <class>` line draws a device
//!   as that class only when the class has as many terminals as the one
//!   it replaces: every pin drawn before stays drawn. `initDevices`
//! - schematic.12 (habit) A device's row line passes through the middle
//!   of its left and right pins, its column line through the middle of
//!   its upper and lower pins: with several on a side, the middle one's
//!   line, pin or not. So two pins facing each other stand on one line.
//!   People: 6,581 of the 6,694 nets of two pins facing each other along
//!   a row or a column in 5,263 hand-drawn schematics. `settleDevices`
//! - schematic.13 (unmeasured) An amplifier symbol's reference terminal
//!   on ground (the class marks it: a controlled source's minus output),
//!   like a MOS body, is part of the symbol and gets no wire. The hand
//!   drawings draw no `E` as an amplifier to test it on; a two-pin
//!   source's minus on ground is a pin with its wire there, in 164 of
//!   164, and here. `referencePin`
//! - schematic.14 (choice) An upright device is its symbol turned a
//!   quarter left, then flipped as the layout asks: unflipped, a MOSFET's
//!   drain is up, its gate left, its source down. People: the gate left
//!   of 17,977 of 28,715 upright transistors, right of the rest: a side
//!   the layout chooses, not this form. `form`
//!
//! Contents:
//! - `pub const structure`, `pub const skeleton`, `pub const sketch`
//! - `pub const Circuit`, `pub const DeviceKind`, `pub const Side`, `pub const Library`, `pub const ClassId`, `pub const Orient`, `pub const Pt`
//! - `pub const none: u32`, `pub const max_pins`
//! - `pub const Role = enum(u8)`, `Role.isRail(r: Role) bool`, `Role.isPort(r: Role) bool`, `pub const Orientation = enum(u1)`
//! - `pub const DeviceInfo = struct`, `pub const NodeKind = enum(u8)`, `pub const Node = struct`, `pub const Pin = struct`, `pub const Route = struct`
//! - `pub const Schematic = struct`, `Schematic.deinit`, `Schematic.pinSide`, `Schematic.reach`, `Schematic.pinPoint`, `Schematic.deviceNode`, `Schematic.boxAt`, `Schematic.addNode`, `Schematic.addPin`
//! - `pub fn guessRoles(gpa: Allocator, nl: *const netlist.Netlist) Allocator.Error![]Role`
//! - `pub fn isReference(nl: *const netlist.Netlist, roles: []const Role, net: u32) bool`
//! - `pub fn roleWord(word: []const u8) ?Role`
//! - `pub fn initDevices(gpa: Allocator, nl: *const netlist.Netlist, roles: []const Role, lib: *Library) !Schematic`
//! - `pub fn settleDevices(s: *Schematic, circuit: *const Circuit.Graph) void`
//! - `pub fn isDriver(circuit: *const Circuit.Graph, roles: []const Role, d: u32) bool`
//! - `pub fn referencePin(s: *const Schematic, d: u32, pin: usize, net: u32) bool`
//! - `pub fn form(o: Orientation) Orient`

const std = @import("std");
const hints = @import("hints.zig");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const netlist = @import("netlist.zig");
const csr = @import("csr.zig");
const device = @import("device.zig");
const library = @import("library.zig");
const forms = @import("forms.zig");
/// Stage 2 (issue #8): blocks, symmetry and a canonical order.
pub const structure = @import("structure.zig");
/// Stage 3 (issue #8): devices on a lattice of rows and columns.
pub const skeleton = @import("skeleton.zig");
/// Stage 4 (issue #8): a drawing from the skeleton.
pub const sketch = @import("sketch.zig");

const EdgeId = csr.EdgeId;

pub const Circuit = netlist.Circuit;
pub const DeviceKind = netlist.DeviceKind;
pub const Side = library.Side;
pub const Library = library.Library;
pub const ClassId = library.ClassId;
pub const Orient = library.Orient;
pub const Pt = library.Pt;

/// No node, pin, net or device.
pub const none: u32 = std.math.maxInt(u32);

/// Card pins past this many are not drawn. A block has one per port, so it
/// is generous.
pub const max_pins = 64;

pub const Role = enum(u8) {
    internal,
    supply,
    sink,
    input,
    output,
    bias,

    /// A supply or a ground: the two ends of the rows' order of potential.
    pub fn isRail(r: Role) bool {
        return r == .supply or r == .sink;
    }

    /// An input, an output or a bias: a net the drawing shows a port for,
    /// its name beside it.
    pub fn isPort(r: Role) bool {
        return r == .input or r == .output or r == .bias;
    }
};

pub const Orientation = enum(u1) { vertical, horizontal };

pub const DeviceInfo = struct {
    /// Drawn in the circuit: drivers of terminal nets and pinless devices
    /// are not (R3).
    kept: bool,
    /// A source driving a terminal net from the sink (R3): drawn apart, as
    /// an island with its own terminal symbols (`Placed`).
    driver: bool,
    orientation: Orientation,
    flip_x: bool,
    flip_y: bool,
    /// What the device is drawn as (library.zig).
    class: ClassId,
    /// The class's placement: orientation and flips as mirror-and-rotate.
    orient: Orient,
    /// Where the device's row and column lines cross, from its origin: the
    /// x of its up/down pins and the y of its left/right pins, placed.
    grid: Pt,
    /// Per side (`@backingInt(Side)`): how far its pins reach from `grid`.
    reach: [4]i32,
};

pub const NodeKind = enum(u8) { device, terminal, label };

pub const Node = struct {
    kind: NodeKind,
    /// device: device index; terminal and label: net index.
    ref: u32,
    /// The node this one is a copy of (a device's pin off its line), else
    /// itself.
    group: u32,
};

pub const Pin = struct {
    /// The node (or copy) the pin is drawn on.
    home: u32,
    side: Side,
    net: u32,
    /// Device index, or `none` for a terminal or label pin.
    device: u32,
    index: u8,
};

/// One wire: a polyline of up to six points.
pub const Route = struct {
    pts: [6][2]f32,
    len: u8,
    net: u32,
};

pub const Schematic = struct {
    arena: std.heap.ArenaAllocator,
    /// The classes devices are drawn as. Borrowed.
    lib: *const Library,
    // Borrowed from the circuit's heap storage: valid while the netlist
    // lives, however the Netlist and Schematic structs are moved.
    device_kind: []const DeviceKind,
    device_name: []const []const u8,
    net_name: []const []const u8,
    device_pin_count: []const u8,
    roles: []const Role,

    devices: std.MultiArrayList(DeviceInfo) = .empty,
    nodes: std.MultiArrayList(Node) = .empty,
    pins: std.MultiArrayList(Pin) = .empty,
    /// Per net: drawn with labels.
    /// Per device, the side a `*@ refdes` line puts its name on; empty for none.
    refdes: []const ?Side = &.{},
    labeled: []bool = &.{},
    /// Each node's point, in the target's units.
    xy: [][2]f32 = &.{},
    /// Device pins alone on their net, drawn with a no-connect mark.
    no_connects: std.ArrayList(u32) = .empty,
    routes: std.ArrayList(Route) = .empty,

    pub fn deinit(self: *Schematic) void {
        self.arena.deinit();
        self.* = undefined;
    }

    /// Side a device pin faces after orientation, flips and mirroring.
    pub fn pinSide(self: *const Schematic, d: u32, pin: usize) ?Side {
        const info = self.devices.get(d);
        var side = baseSide(self, d, info.orientation, pin) orelse return null;
        if (info.flip_x) side = side.flipX();
        if (info.flip_y) side = side.flipY();
        return side;
    }

    /// How far a node's pins facing `side` reach from its point, in the
    /// target's units: the class geometry for devices, zero for terminals
    /// and labels (they connect at their point).
    pub fn reach(self: *const Schematic, node: u32, side: Side) f32 {
        if (self.nodes.items(.kind)[node] != .device) return 0;
        const d = self.nodes.items(.ref)[node];
        return @floatFromInt(self.devices.items(.reach)[d][@backingInt(side)]);
    }

    /// Where a wire meets pin `pin`: on its node's line, at its side's
    /// reach. Along the pin's own axis, a copy's pin sits where its device
    /// has it.
    pub fn pinPoint(self: *const Schematic, pin: u32) [2]f32 {
        const node = self.pins.items(.home)[pin];
        const side = self.pins.items(.side)[pin];
        var p = self.xy[node];
        if (self.nodes.items(.kind)[node] == .device) {
            const ax: usize = if (side.isHorizontal()) 0 else 1;
            p[ax] = self.xy[self.nodes.items(.group)[node]][ax];
        }
        const v = side.vec();
        const d = self.reach(node, side);
        return .{ p[0] + d * v[0], p[1] + d * v[1] };
    }

    /// The node a device's symbol is drawn on (not a copy of it).
    pub fn deviceNode(self: *const Schematic, d: u32) ?u32 {
        const kinds = self.nodes.items(.kind);
        for (kinds, self.nodes.items(.ref), self.nodes.items(.group), 0..) |k, r, g, i| {
            if (k == .device and r == d and g == i) return @intCast(i);
        }
        return null;
    }

    /// Device `d`'s symbol as it is turned (`orient`, `grid`: settled), with
    /// its grid point at `at`.
    pub fn boxAt(self: *const Schematic, d: usize, at: Pt) library.Rect {
        const info = self.devices.slice();
        return self.lib.at(info.items(.class)[d]).box(info.items(.orient)[d], at.sub(info.items(.grid)[d]));
    }

    pub fn addNode(self: *Schematic, node: Node) !u32 {
        const id: u32 = @intCast(self.nodes.len);
        var n = node;
        if (n.group == none) n.group = id;
        try self.nodes.append(self.arena.allocator(), n);
        return id;
    }

    pub fn addPin(self: *Schematic, pin: Pin) !u32 {
        const id: u32 = @intCast(self.pins.len);
        try self.pins.append(self.arena.allocator(), pin);
        return id;
    }
};

/// R1: by name. R2: nets driven from ground by a V source. Edit the result
/// freely before laying out.
pub fn guessRoles(gpa: Allocator, nl: *const netlist.Netlist) Allocator.Error![]Role {
    const circuit = &nl.graph;
    const names = circuit.vertices.items(.name);
    const roles = try gpa.alloc(Role, names.len);
    for (names, roles, 0..) |name, *r, i| r.* = if (i == 0) .sink else roleFromName(name);
    // A reference comes from outside (R1) unless a transistor's drain or
    // collector makes it here: then it is what the circuit puts out.
    for (circuit.edges.items(.kind), 0..) |k, d| {
        if (!device.isTransistor(k)) continue;
        const pins = circuit.members(EdgeId.from(d));
        const upper = device.of(k).path.?[0];
        const made = if (pins.len > upper) pins[upper].index() else 0; // net 0: the sink, never an input
        if (roles[made] == .input and library.named(names[made], .net) == .ref) roles[made] = .output;
    }

    const order = try hints.applyOrder(gpa, nl.hints);
    defer gpa.free(order);
    // A source a `*@ driver <src> inline` line draws in the circuit drives
    // no terminal net: R2 passes it.
    const in_circuit = try gpa.alloc(bool, circuit.edgeCount());
    defer gpa.free(in_circuit);
    @memset(in_circuit, false);
    for (order) |i| {
        const h = nl.hints[i];
        if (h.verb != .driver or h.args.len != 2) continue;
        const d = nl.device(h.args[0]) orelse continue;
        in_circuit[d.index()] = std.mem.eql(u8, h.args[1], "inline");
    }
    for (0..circuit.edgeCount()) |d| {
        const net = driven(circuit, roles, d) orelse continue;
        if (in_circuit[d] or roles[net] != .internal) continue;
        roles[net] = if (isSignalSource(nl, @intCast(d))) .input else .bias;
    }
    // A circuit with no pin on a ground stands on a reference all the same
    // (`reference`), unless a line of the deck names its ground.
    const told = for (nl.hints) |h| {
        if (h.verb == .role and h.args.len == 2 and roleWord(h.args[1]) == .sink) break true;
    } else false;
    if (!told) if (try reference(gpa, nl, roles)) |net| {
        roles[net] = .sink;
    };
    // The deck's `*@ role <net> <role>` lines, the preferred one last.
    for (order) |i| {
        const h = nl.hints[i];
        if (h.verb != .role or h.args.len != 2) continue;
        const net = nl.net(h.args[0]) orelse continue;
        roles[net.index()] = roleWord(h.args[1]) orelse continue;
    }
    assert(roles.len == circuit.vertexCount());
    return roles;
}

/// Whether `net` is the reference `guessRoles` gave a circuit with no
/// ground: a sink no name and no line of the deck calls a ground. It is
/// drawn as the circuit's bottom wire, not as a ground.
pub fn isReference(nl: *const netlist.Netlist, roles: []const Role, net: u32) bool {
    assert(roles.len == nl.graph.vertexCount());
    if (net == 0 or roles[net] != .sink or roleFromName(nl.graph.vertices.items(.name)[net]) == .sink) return false;
    for (nl.hints) |h| {
        if (h.verb != .role or h.args.len != 2 or roleWord(h.args[1]) != .sink) continue;
        if ((nl.net(h.args[0]) orelse continue).index() == net) return false;
    }
    return true;
}

/// The role a `*@ role` line names (`ground` is the sink), or null.
pub fn roleWord(word: []const u8) ?Role {
    if (std.mem.eql(u8, word, "ground")) return .sink;
    const r = std.meta.stringToEnum(Role, word) orelse return null;
    return if (r == .sink) null else r;
}

/// A schematic with its devices' classes and nothing else: no orientation,
/// node, pin or wire (`sketch.zig` goes on from here).
pub fn initDevices(gpa: Allocator, nl: *const netlist.Netlist, roles: []const Role, lib: *Library) !Schematic {
    const circuit = &nl.graph;
    assert(roles.len == circuit.vertexCount());
    const classes = try gpa.alloc(ClassId, circuit.edgeCount());
    defer gpa.free(classes);
    for (classes, circuit.edges.items(.kind), 0..) |*c, k, d| {
        const e = EdgeId.from(d);
        c.* = if (nl.defOf(e)) |def| try lib.blockFor(def) else try lib.classFor(k, nl.modelType(e), circuit.members(e).len);
        // An `E` that is a dependent source, not the book's amplifier: the
        // library's two-pin `vcvs`, where it has one. People: a two-pin
        // source symbol for 37 of 37 `E` cards (464 of 464 with G, F, H).
        if (k == .vcvs and forms.isDependent(nl, roles, @intCast(d))) c.* = lib.find("vcvs") orelse c.*;
    }
    // The deck's `*@ class <dev> <class>` lines, the preferred one last: a
    // class with as many terminals as the one it replaces draws every pin
    // it did.
    const order = try hints.applyOrder(gpa, nl.hints);
    defer gpa.free(order);
    for (order) |i| {
        const h = nl.hints[i];
        if (h.verb != .class or h.args.len != 2) continue;
        const e = nl.device(h.args[0]) orelse continue;
        const id = lib.find(h.args[1]) orelse continue;
        if (lib.at(id).terminals.len < lib.at(classes[e.index()]).terminals.len) continue;
        classes[e.index()] = id;
    }
    var s: Schematic = .{
        .arena = .init(gpa),
        .lib = lib,
        .device_kind = circuit.edges.items(.kind),
        .device_name = circuit.edges.items(.name),
        .net_name = circuit.vertices.items(.name),
        .device_pin_count = &.{},
        .roles = &.{},
    };
    errdefer s.arena.deinit();
    const a = s.arena.allocator();
    s.roles = try a.dupe(Role, roles);
    const counts = try a.alloc(u8, circuit.edgeCount());
    for (counts, 0..) |*c, d| c.* = @intCast(circuit.members(EdgeId.from(d)).len);
    s.device_pin_count = counts;
    s.labeled = try a.alloc(bool, circuit.vertexCount());
    @memset(s.labeled, false);
    try s.devices.resize(a, circuit.edgeCount());
    @memcpy(s.devices.items(.class), classes);
    assert(s.devices.len == circuit.edgeCount());
    return s;
}

/// Each device's placement from its orientation and flips: its `orient`,
/// where its row and column lines cross (`grid`), and how far its drawn
/// pins reach from there per side.
pub fn settleDevices(s: *Schematic, circuit: *const Circuit.Graph) void {
    const info = s.devices.slice();
    assert(info.len == circuit.edgeCount());
    for (0..circuit.edgeCount()) |d| {
        const o = Orient.flipped(form(info.items(.orientation)[d]), info.items(.flip_x)[d], info.items(.flip_y)[d]);
        info.items(.orient)[d] = o;
        const c = s.lib.at(info.items(.class)[d]);
        // The middle of the up/down pins' x and of the left/right pins' y:
        // with several pins on a side, the middle one's line, pin or not.
        // People: two pins facing each other stand on one line in 6,581 of
        // 6,694 nets of two such pins.
        var lo: [2]i32 = .{ std.math.maxInt(i32), std.math.maxInt(i32) };
        var hi: [2]i32 = .{ std.math.minInt(i32), std.math.minInt(i32) };
        const members = circuit.members(EdgeId.from(d));
        for (c.terminals, 0..) |t, i| {
            if (i >= members.len or referencePin(s, @intCast(d), i, members[i].index())) continue;
            const side = c.side(i, o) orelse continue;
            const p = o.apply(t.at);
            const ax: usize = if (side.isHorizontal()) 1 else 0;
            const v = if (ax == 0) p.x else p.y;
            lo[ax] = @min(lo[ax], v);
            hi[ax] = @max(hi[ax], v);
        }
        var grid: Pt = .zero;
        if (lo[0] <= hi[0]) grid.x = @divFloor(lo[0] + hi[0], 2);
        if (lo[1] <= hi[1]) grid.y = @divFloor(lo[1] + hi[1], 2);
        var reach: [4]i32 = @splat(0);
        for (c.terminals, 0..) |t, i| {
            if (i >= members.len or referencePin(s, @intCast(d), i, members[i].index())) continue;
            const side = c.side(i, o) orelse continue;
            const p = o.apply(t.at).sub(grid);
            const r: i32 = @intCast(if (side.isHorizontal()) @abs(p.x) else @abs(p.y));
            reach[@backingInt(side)] = @max(reach[@backingInt(side)], r);
        }
        info.items(.grid)[d] = grid;
        info.items(.reach)[d] = reach;
    }
}

/// R3: a V source from the sink to a supply, input or bias net drives a
/// terminal net: drawn apart, not in the circuit.
pub fn isDriver(circuit: *const Circuit.Graph, roles: []const Role, d: u32) bool {
    const r = roles[driven(circuit, roles, d) orelse return false];
    return r == .supply or r == .input or r == .bias;
}

/// A controlled source's out- on the sink is the op-amp's reference: like a
/// MOS bulk it is a pin of the card but not drawn.
pub fn referencePin(s: *const Schematic, d: u32, pin: usize, net: u32) bool {
    const c = s.lib.at(s.devices.items(.class)[d]);
    return pin < c.terminals.len and c.terminals[pin].ground_ref and s.roles[net] == .sink;
}

/// The class as drawn is the horizontal form; the vertical form is it
/// turned a quarter left.
pub fn form(o: Orientation) Orient {
    // The unflipped upright form has its gate left: where people draw it
    // on 17,977 of 28,715 upright transistors, the layout's flip the rest.
    return if (o == .vertical) .left else .r0;
}

// ---- private ----

/// A pin's side in form `o`, or null: not drawn (a MOS bulk, a terminal the
/// class lacks).
fn baseSide(s: *const Schematic, d: u32, o: Orientation, pin: usize) ?Side {
    if (pin >= max_pins) return null;
    return s.lib.at(s.devices.items(.class)[d]).side(pin, form(o));
}

/// R1: a net's role by its name (`library.named`). A reference comes from
/// outside, as an amplifier's inputs do.
fn roleFromName(name: []const u8) Role {
    // People, on the nets so named in 5,263 hand-drawn schematics: rail
    // symbols and no port on 4,010 of 4,157 supplies and 5,467 of 5,535
    // grounds; a port on 2,926 of 3,241 bias lines no drain makes; a port
    // and no output on 2,650 of 2,677 inputs and 580 of 627 references; a
    // port and no input on 3,894 of 3,935 outputs.
    return switch (library.named(name, .net) orelse return .internal) {
        .supply => .supply,
        .ground => .sink,
        .bias => .bias,
        .ref, .inp, .inn, .in => .input,
        .out => .output,
    };
}

/// R2, R3: the net a V source drives from the sink, its other end; null
/// for any other device, and for a source with no end on the sink. Only a
/// voltage source sets a net's potential: a current source drives none.
fn driven(circuit: *const Circuit.Graph, roles: []const Role, d: usize) ?u32 {
    if (circuit.edges.items(.kind)[d] != .vsource) return null;
    const pins = circuit.members(EdgeId.from(d));
    if (pins.len < 2) return null;
    const a = pins[0].index();
    const b = pins[1].index();
    return if (roles[b] == .sink) a else if (roles[a] == .sink) b else null;
}

/// The net a circuit of parts with no pin on a ground stands on, or null
/// when it has a ground, or a transistor (its rails are then named, and a
/// gate line is no reference): the internal net of two pins or more that most two-pin cards
/// end on (their second pin, less their first; a voltage source's minus
/// and the pin a current source draws from count double), then the one
/// with the most pins, then by name. People draw such a circuit over one
/// bottom wire (172 of 191 connected pieces in 5,263 hand-drawn
/// schematics), and that score names the wire in 77.9%.
fn reference(gpa: Allocator, nl: *const netlist.Netlist, roles: []const Role) Allocator.Error!?u32 {
    const circuit = &nl.graph;
    const n = circuit.vertexCount();
    assert(roles.len == n);
    for (roles, 0..) |r, v| {
        if (r == .sink and circuit.incident(csr.VertexId.from(@intCast(v))).len > 0) return null;
    }
    for (circuit.edges.items(.kind)) |k| if (device.isTransistor(k)) return null;
    const score = try gpa.alloc(i32, n);
    defer gpa.free(score);
    @memset(score, 0);
    for (circuit.edges.items(.kind), 0..) |k, d| {
        const pins = circuit.members(EdgeId.from(d));
        // A card of just two pins, whatever its kind: wider than the device
        // table's parts (`device.isPart`) by a B source and a two-port
        // block, narrower by a part with a third pin (a body, a control
        // pair). Only an independent source's low end counts double:
        // counting a controlled source's too names the bottom wire people
        // draw in 47 of the 63 circuits that hold one, against 50.
        if (pins.len != 2) continue;
        if (device.of(k).source == .independent) {
            score[pins[device.lowEnd(k)].index()] += 2;
        } else {
            score[pins[1].index()] += 1;
            score[pins[0].index()] -= 1;
        }
    }
    const names = circuit.vertices.items(.name);
    var best: ?u32 = null;
    for (0..n) |v| {
        const pins = circuit.incident(csr.VertexId.from(@intCast(v))).len;
        if (roles[v] != .internal or pins < 2) continue;
        const b = best orelse {
            best = @intCast(v);
            continue;
        };
        const b_pins = circuit.incident(csr.VertexId.from(b)).len;
        if (score[v] != score[b]) {
            if (score[v] > score[b]) best = @intCast(v);
        } else if (pins != b_pins) {
            if (pins > b_pins) best = @intCast(v);
        } else if (std.mem.lessThan(u8, names[v], names[b])) best = @intCast(v);
    }
    return best;
}

/// R2: a source with a signal (AC, a waveform) drives an input; else a bias.
fn isSignalSource(nl: *const netlist.Netlist, d: u32) bool {
    const signal_words = [_][]const u8{ "ac", "sin", "pulse", "pwl", "exp", "sffm", "am", "trnoise", "trrandom" };
    for (nl.params(EdgeId.from(d))) |tok| {
        for (signal_words) |w| if (std.mem.eql(u8, tok, w)) return true;
    }
    return false;
}

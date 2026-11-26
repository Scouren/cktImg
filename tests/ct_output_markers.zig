//! Complete four-side stage -> four actual passive-circle markers outside branches.
//! Oracle: source SVG pP1/pP2 face left, pM1/pM2 right, with twenty actual
//! marker-to-local-pin paths and four whole-ink remote-gate negatives.
//! R/series-output-markers.json preserves this one-figure evidence. Circle
//! shape establishes no electrical direction; weak DUT roles remain output.
//! The source72 endpoints/90 bindings/148 pairs below are unchanged literals
//! from ct_four_sides.zig. This future suite is unimported until trusted RED.
//!
//! Contents: frozen source data, actual marker and partition readers, tests.

const std = @import("std");
const testing = std.testing;
const np = @import("NetlistParser");
const support = @import("support.zig");
const ink = @import("wire_ink.zig");
const deck = @embedFile("ct_series_tanks_fixture.sp");
const Endpoint=struct {card:[]const u8,index:u8,net:[]const u8,source:np.Pt,part:u8};
const endpoints=[_]Endpoint{
    .{.card="c1",.index=0,.net="m2",.source=.{.x=320,.y=150},.part=8},
    .{.card="c1",.index=1,.net="p2",.source=.{.x=280,.y=150},.part=6},
    .{.card="c2",.index=0,.net="m1",.source=.{.x=320,.y=350},.part=12},
    .{.card="c2",.index=1,.net="p1",.source=.{.x=280,.y=350},.part=10},
    .{.card="ls1",.index=0,.net="p2",.source=.{.x=230,.y=160},.part=6},
    .{.card="ls1",.index=1,.net="p4",.source=.{.x=230,.y=200},.part=0},
    .{.card="ls2",.index=0,.net="m2",.source=.{.x=370,.y=160},.part=8},
    .{.card="ls2",.index=1,.net="m4",.source=.{.x=370,.y=200},.part=1},
    .{.card="ls3",.index=0,.net="p3",.source=.{.x=230,.y=300},.part=2},
    .{.card="ls3",.index=1,.net="p1",.source=.{.x=230,.y=340},.part=10},
    .{.card="ls4",.index=0,.net="m3",.source=.{.x=370,.y=300},.part=4},
    .{.card="ls4",.index=1,.net="m1",.source=.{.x=370,.y=340},.part=12},
    .{.card="m10",.index=0,.net="p2",.source=.{.x=180,.y=100},.part=6},
    .{.card="m10",.index=1,.net="m2",.source=.{.x=150,.y=80},.part=9},
    .{.card="m10",.index=2,.net="vss",.source=.{.x=180,.y=60},.part=19},
    .{.card="m11",.index=0,.net="m2",.source=.{.x=420,.y=100},.part=8},
    .{.card="m11",.index=1,.net="p2",.source=.{.x=450,.y=80},.part=7},
    .{.card="m11",.index=2,.net="vss",.source=.{.x=420,.y=60},.part=20},
    .{.card="m12",.index=0,.net="p2",.source=.{.x=210,.y=100},.part=6},
    .{.card="m12",.index=1,.net="m2",.source=.{.x=240,.y=80},.part=8},
    .{.card="m12",.index=2,.net="net2",.source=.{.x=210,.y=60},.part=14},
    .{.card="m13",.index=0,.net="m2",.source=.{.x=390,.y=100},.part=8},
    .{.card="m13",.index=1,.net="p2",.source=.{.x=360,.y=80},.part=6},
    .{.card="m13",.index=2,.net="net2",.source=.{.x=390,.y=60},.part=14},
    .{.card="m14",.index=0,.net="net2",.source=.{.x=300,.y=60},.part=14},
    .{.card="m14",.index=1,.net="lb",.source=.{.x=270,.y=40},.part=27},
    .{.card="m14",.index=2,.net="vss",.source=.{.x=300,.y=20},.part=21},
    .{.card="m15",.index=0,.net="p4",.source=.{.x=210,.y=230},.part=0},
    .{.card="m15",.index=1,.net="p3",.source=.{.x=180,.y=250},.part=3},
    .{.card="m15",.index=2,.net="net0",.source=.{.x=210,.y=270},.part=16},
    .{.card="m16",.index=0,.net="p3",.source=.{.x=90,.y=230},.part=3},
    .{.card="m16",.index=1,.net="p4",.source=.{.x=120,.y=250},.part=0},
    .{.card="m16",.index=2,.net="net0",.source=.{.x=90,.y=270},.part=16},
    .{.card="m17",.index=0,.net="net0",.source=.{.x=150,.y=270},.part=16},
    .{.card="m17",.index=1,.net="hb",.source=.{.x=120,.y=290},.part=31},
    .{.card="m17",.index=2,.net="vss",.source=.{.x=150,.y=310},.part=22},
    .{.card="m18",.index=0,.net="p4",.source=.{.x=170,.y=190},.part=0},
    .{.card="m18",.index=1,.net="lb",.source=.{.x=150,.y=160},.part=28},
    .{.card="m18",.index=2,.net="p3",.source=.{.x=130,.y=190},.part=3},
    .{.card="m19",.index=0,.net="m4",.source=.{.x=390,.y=230},.part=1},
    .{.card="m19",.index=1,.net="m3",.source=.{.x=420,.y=250},.part=5},
    .{.card="m19",.index=2,.net="net3",.source=.{.x=390,.y=270},.part=17},
    .{.card="m20",.index=0,.net="m3",.source=.{.x=510,.y=230},.part=5},
    .{.card="m20",.index=1,.net="m4",.source=.{.x=480,.y=250},.part=1},
    .{.card="m20",.index=2,.net="net3",.source=.{.x=510,.y=270},.part=17},
    .{.card="m21",.index=0,.net="net3",.source=.{.x=450,.y=270},.part=17},
    .{.card="m21",.index=1,.net="hb",.source=.{.x=480,.y=290},.part=32},
    .{.card="m21",.index=2,.net="vss",.source=.{.x=450,.y=310},.part=23},
    .{.card="m22",.index=0,.net="m4",.source=.{.x=430,.y=190},.part=1},
    .{.card="m22",.index=1,.net="lb",.source=.{.x=450,.y=160},.part=29},
    .{.card="m22",.index=2,.net="m3",.source=.{.x=470,.y=190},.part=5},
    .{.card="m5",.index=0,.net="p1",.source=.{.x=180,.y=400},.part=10},
    .{.card="m5",.index=1,.net="m1",.source=.{.x=150,.y=420},.part=13},
    .{.card="m5",.index=2,.net="vss",.source=.{.x=180,.y=440},.part=24},
    .{.card="m6",.index=0,.net="m1",.source=.{.x=420,.y=400},.part=12},
    .{.card="m6",.index=1,.net="p1",.source=.{.x=450,.y=420},.part=11},
    .{.card="m6",.index=2,.net="vss",.source=.{.x=420,.y=440},.part=25},
    .{.card="m7",.index=0,.net="p1",.source=.{.x=210,.y=400},.part=10},
    .{.card="m7",.index=1,.net="m1",.source=.{.x=240,.y=420},.part=12},
    .{.card="m7",.index=2,.net="net1",.source=.{.x=210,.y=440},.part=15},
    .{.card="m8",.index=0,.net="m1",.source=.{.x=390,.y=400},.part=12},
    .{.card="m8",.index=1,.net="p1",.source=.{.x=360,.y=420},.part=10},
    .{.card="m8",.index=2,.net="net1",.source=.{.x=390,.y=440},.part=15},
    .{.card="m9",.index=0,.net="net1",.source=.{.x=300,.y=440},.part=15},
    .{.card="m9",.index=1,.net="lb",.source=.{.x=270,.y=460},.part=30},
    .{.card="m9",.index=2,.net="vss",.source=.{.x=300,.y=480},.part=26},
    .{.card="xl1",.index=0,.net="p4",.source=.{.x=250,.y=210},.part=0},
    .{.card="xl1",.index=1,.net="m4",.source=.{.x=350,.y=210},.part=1},
    .{.card="xl1",.index=2,.net="vdd",.source=.{.x=300,.y=230},.part=18},
    .{.card="xl2",.index=0,.net="p3",.source=.{.x=250,.y=290},.part=2},
    .{.card="xl2",.index=1,.net="m3",.source=.{.x=350,.y=290},.part=4},
    .{.card="xl2",.index=2,.net="vdd",.source=.{.x=300,.y=270},.part=18},
};
const contracts=[_]struct {card:[]const u8,nets:[]const []const u8}{
    .{.card="c1",.nets=&.{"m2","p2"}},
    .{.card="c2",.nets=&.{"m1","p1"}},
    .{.card="ls1",.nets=&.{"p2","p4"}},
    .{.card="ls2",.nets=&.{"m2","m4"}},
    .{.card="ls3",.nets=&.{"p3","p1"}},
    .{.card="ls4",.nets=&.{"m3","m1"}},
    .{.card="m10",.nets=&.{"p2","m2","vss","vss"}},
    .{.card="m11",.nets=&.{"m2","p2","vss","vss"}},
    .{.card="m12",.nets=&.{"p2","m2","net2","vss"}},
    .{.card="m13",.nets=&.{"m2","p2","net2","vss"}},
    .{.card="m14",.nets=&.{"net2","lb","vss","vss"}},
    .{.card="m15",.nets=&.{"p4","p3","net0","vss"}},
    .{.card="m16",.nets=&.{"p3","p4","net0","vss"}},
    .{.card="m17",.nets=&.{"net0","hb","vss","vss"}},
    .{.card="m18",.nets=&.{"p4","lb","p3","vss"}},
    .{.card="m19",.nets=&.{"m4","m3","net3","vss"}},
    .{.card="m20",.nets=&.{"m3","m4","net3","vss"}},
    .{.card="m21",.nets=&.{"net3","hb","vss","vss"}},
    .{.card="m22",.nets=&.{"m4","lb","m3","vss"}},
    .{.card="m5",.nets=&.{"p1","m1","vss","vss"}},
    .{.card="m6",.nets=&.{"m1","p1","vss","vss"}},
    .{.card="m7",.nets=&.{"p1","m1","net1","vss"}},
    .{.card="m8",.nets=&.{"m1","p1","net1","vss"}},
    .{.card="m9",.nets=&.{"net1","lb","vss","vss"}},
    .{.card="xl1",.nets=&.{"p4","m4","vdd"}},
    .{.card="xl2",.nets=&.{"p3","m3","vdd"}},
};
const Frame=[endpoints.len]np.Pt;
const Actual=struct {points:Frame,pins:[endpoints.len]usize};


const Case = struct { net: []const u8, part: u8, remote: u8, side: np.library.Side, source: np.Pt };
const cases = [_]Case{
    .{ .net="p2", .part=6, .remote=7, .side=.left, .source=.{.x=140,.y=120} },
    .{ .net="m2", .part=8, .remote=9, .side=.right, .source=.{.x=460,.y=120} },
    .{ .net="p1", .part=10, .remote=11, .side=.left, .source=.{.x=140,.y=380} },
    .{ .net="m1", .part=12, .remote=13, .side=.right, .source=.{.x=460,.y=380} },
};
const Marker = struct { pin: usize, at: np.Pt, from: np.Pt };

// ---- private ----

fn netIn(p: *const np.Placed, name: []const u8) ?u32 {
    for (p.net_name,0..) |n,i| if (std.mem.eql(u8,n,name)) return @intCast(i);
    return null;
}
fn outside(points: [5]np.Pt, at: np.Pt, side: np.library.Side) bool {
    for (points) |p| {
        if (side == .left and at.x >= p.x) return false;
        if (side == .right and at.x <= p.x) return false;
    }
    return side == .left or side == .right;
}
fn facing(at: np.Pt, from: np.Pt, side: np.library.Side) bool {
    return at.y == from.y and (if (side == .left) at.x < from.x else if (side == .right) at.x > from.x else false);
}
fn hollow(ops: []const np.library.DrawOp, local_pin: np.Pt) bool {
    if (ops.len != 1 or ops[0] != .circle) return false;
    return ops[0].circle.r > 0 and ops[0].circle.c.eql(local_pin);
}
fn pinIndex(card: []const u8, index: usize, changed: bool) usize {
    if (!changed) return index;
    return switch (card[0]) { 'c', 'l' => 1-index, 'x' => 2-index, else => index };
}
fn native(p: *const np.Placed, lib: *const np.Library, changed: bool) !Actual {
    var named: usize=0;
    for (p.dev_name) |name| if (name.len!=0) { named+=1; };
    try testing.expectEqual(contracts.len,named);
    var raw: usize=0;
    for (contracts) |contract| {
        const d=np.checks.deviceIn(p,contract.card) orelse return error.MissingCard;
        const lo,const hi=p.pinRange(d);
        try testing.expectEqual(contract.nets.len,hi-lo);
        for (contract.nets,0..) |net,i| {
            try testing.expectEqualStrings(net,p.net_name[p.pin_net[lo+pinIndex(contract.card,i,changed)]]);
            raw+=1;
        }
    }
    try testing.expectEqual(@as(usize,90),raw);
    var actual: Actual=undefined;
    for (endpoints,0..) |e,i| {
        const d=np.checks.deviceIn(p,e.card).?;
        const j=pinIndex(e.card,e.index,changed);
        const pin=p.dev_pin0[d]+j;
        const class=lib.at(p.dev_class[d]);
        try testing.expect(class.shows(j));
        try testing.expectEqualStrings(e.net,p.net_name[p.pin_net[pin]]);
        const tip=p.dev_pos[d].add(p.dev_orient[d].apply(class.terminals[j].at));
        try testing.expectEqualDeep(tip,p.pin_xy[pin]);
        actual.points[i]=tip;actual.pins[i]=pin;
    }
    return actual;
}
fn allPairs(p: *const np.Placed, actual: Actual) !void {
    var checked: usize=0;
    for (endpoints,0..) |a,i| for (endpoints[i+1..],i+1..) |b,j| {
        if (!std.mem.eql(u8,a.net,b.net)) continue;
        const got=try ink.connected(testing.allocator,p,&.{actual.pins[i],actual.pins[j]});
        errdefer std.debug.print("marker prerequisite {s}:{s}.{}--{s}.{} expected={} got={}\n",.{a.net,a.card,a.index,b.card,b.index,a.part==b.part,got});
        try testing.expectEqual(a.part==b.part,got);checked+=1;
    };
    try testing.expectEqual(@as(usize,148),checked);
}
fn marker(p: *const np.Placed, lib: *const np.Library, net: u32) !Marker {
    var selected: ?usize=null;
    for (p.dev_name,0..) |name,d| {
        if (name.len!=0) continue;
        const class=lib.at(p.dev_class[d]);
        if (class.role!=.output_port) continue;
        const lo,const hi=p.pinRange(d);
        if (hi-lo!=1 or p.pin_net[lo]!=net) continue;
        if (selected!=null) return error.AmbiguousMarker;
        if (class.terminals.len!=1 or !class.shows(0) or !hollow(class.draw,class.terminals[0].at)) return error.NotHollowCircle;
        const at=p.dev_pos[d].add(p.dev_orient[d].apply(class.terminals[0].at));
        if (!at.eql(p.pin_xy[lo])) return error.ProjectedMarker;
        selected=lo;
    }
    const pin=selected orelse return error.MissingMarker;
    const at=p.pin_xy[pin];var from: ?np.Pt=null;
    for (p.net_seg[net]..p.net_seg[net+1]) |segment| {
        const points=p.wire_pts[p.seg_pt[segment]..p.seg_pt[segment+1]];
        try testing.expect(points.len>=2);
        for (points[0..points.len-1],points[1..]) |a,b| {
            const neighbor=if (a.eql(at)) b else if (b.eql(at)) a else continue;
            if (from!=null) return error.AmbiguousMarkerStub;
            from=neighbor;
        }
    }
    return .{.pin=pin,.at=at,.from=from orelse return error.MissingMarkerStub};
}
fn sourceParts(p: *const np.Placed, actual: Actual, case: Case, m: Marker) ![5]np.Pt {
    var points: [5]np.Pt=undefined;var count: usize=0;var remote: usize=0;
    for (endpoints,0..) |e,i| {
        if (e.part==case.part) {
            try testing.expectEqualStrings(case.net,e.net);
            try testing.expectEqual(p.pin_net[actual.pins[i]],p.pin_net[m.pin]);
            try testing.expect(try ink.connected(testing.allocator,p,&.{m.pin,actual.pins[i]}));
            if (count>=points.len) return error.ExtraLocalPin;
            points[count]=actual.points[i];count+=1;
        } else if (e.part==case.remote) {
            try testing.expectEqualStrings(case.net,e.net);
            try testing.expect(!try ink.connected(testing.allocator,p,&.{m.pin,actual.pins[i]}));remote+=1;
        }
    }
    try testing.expectEqual(@as(usize,5),count);try testing.expectEqual(@as(usize,1),remote);
    return points;
}
fn sourceRun(text: []const u8, compact: bool, changed: bool) !void {
    const lib=try support.library(testing.allocator);defer support.freeLibrary(testing.allocator,lib);
    var p=try np.place(testing.allocator,&.{.layout=.{.compact=compact,.shelf=8}},lib,&.{text},null);defer p.deinit();
    const actual=try native(&p,lib,changed);
    try allPairs(&p,actual);
    try support.expectConnected(&p,lib);try testing.expectEqual(@as(u32,0),try support.shorts(testing.allocator,&p,true));
    var matches: [cases.len]bool=undefined;
    for (cases,0..) |case,i| {
        const net=netIn(&p,case.net) orelse return error.MissingNet;
        const m=try marker(&p,lib,net);const points=try sourceParts(&p,actual,case,m);
        matches[i]=outside(points,m.at,case.side) and facing(m.at,m.from,case.side);
        std.debug.print("passive marker {s} compact={} expected={s} tip={any} from={any} outside={} facing={}\n",.{case.net,compact,@tagName(case.side),m.at,m.from,outside(points,m.at,case.side),facing(m.at,m.from,case.side)});
    }
    for (matches) |matches_source| try testing.expect(matches_source);
}
fn changedDeck(a: std.mem.Allocator) ![]const u8 {
    var text: []const u8=deck;
    for ([_][2][]const u8{
        .{"ct_inductor n1 n2 n3 params:","ct_inductor n3 n2 n1 params:"},
        .{"XL1 P4 M4 Vdd ct_inductor","XL1 Vdd M4 P4 ct_inductor"},
        .{"XL2 P3 M3 Vdd ct_inductor","XL2 Vdd M3 P3 ct_inductor"},
        .{"C1 M2 P2 1p","C1 P2 M2 1p"},.{"C2 M1 P1 1p","C2 P1 M1 1p"},
        .{"LS1 P2 P4 1n\nLS2 M2 M4 1n","LS2 M4 M2 1n\nLS1 P4 P2 1n"},
        .{"LS3 P3 P1 1n\nLS4 M3 M1 1n","LS4 M1 M3 1n\nLS3 P1 P3 1n"},
    }) |change| {
        try testing.expect(std.mem.indexOf(u8,text,change[0])!=null);
        text=try std.mem.replaceOwned(u8,a,text,change[0],change[1]);
    }
    return text;
}

test "CT output markers: literal passive circles and outside placement reject independent mutations" {
    const ops=[_]np.library.DrawOp{.circ(0,0,3)};
    try testing.expect(hollow(&ops,.zero));
    try testing.expect(!hollow(&.{},.zero));
    try testing.expect(!hollow(&.{.{.filled_circle=.{.c=.zero,.r=3}}},.zero));
    try testing.expect(!hollow(&ops,.{.x=1,.y=0}));
    for (cases) |case| {
        var points: [5]np.Pt=undefined;var count: usize=0;
        for (endpoints) |e| if (e.part==case.part) { points[count]=e.source;count+=1; };
        try testing.expectEqual(@as(usize,5),count);
        try testing.expect(outside(points,case.source,case.side));
        const from=case.source.add(.{.x=if(case.side==.left) @as(i32,20) else -20,.y=0});
        try testing.expect(facing(case.source,from,case.side));
        try testing.expect(!facing(case.source,from,case.side.opposite()));
        try testing.expect(!outside(points,points[0],case.side));
        const opposite: np.Pt=.{.x=600-case.source.x,.y=case.source.y};
        try testing.expect(!outside(points,opposite,case.side));
        try testing.expect(!facing(case.source,from.add(.{.x=0,.y=1}),case.side));
    }
}

test "CT output markers: all four source sides uncompacted keep ninety bindings and148 pairs" {
    try sourceRun(deck,false,false);
}

test "CT output markers: all four source sides compacted keep ninety bindings and148 pairs" {
    try sourceRun(deck,true,false);
}

test "CT output markers: declaration and passive reversal preserve named marker sides" {
    var arena=std.heap.ArenaAllocator.init(testing.allocator);defer arena.deinit();
    const text=try changedDeck(arena.allocator());
    for ([_]bool{false,true}) |compact| try sourceRun(text,compact,true);
}

test "CT output markers: missing or misbound generated circle fails while148 original pairs stay unchanged" {
    const lib=try support.library(testing.allocator);defer support.freeLibrary(testing.allocator,lib);
    var p=try np.place(testing.allocator,&.{.layout=.{.compact=false,.shelf=8}},lib,&.{deck},null);defer p.deinit();
    const actual=try native(&p,lib,false);try allPairs(&p,actual);
    const net=netIn(&p,"p2").?;const m=try marker(&p,lib,net);
    var altered=p;
    const nets=try testing.allocator.dupe(u32,p.pin_net);defer testing.allocator.free(nets);
    nets[m.pin]=netIn(&p,"lb").?;altered.pin_net=nets;
    try testing.expectError(error.MissingMarker,marker(&altered,lib,net));
    try allPairs(&altered,actual);
    const classes=try testing.allocator.dupe(np.library.ClassId,p.dev_class);defer testing.allocator.free(classes);
    const d=for (p.dev_name,0..) |name,i| { if(name.len==0 and p.dev_pin0[i]==m.pin) break i; } else unreachable;
    classes[d]=try lib.register(.{.name="wrong_filled_marker",.role=.output_port,.terminals=&.{.{.name="p",.at=.zero}},.draw=&.{.{.filled_circle=.{.c=.zero,.r=3}}}});
    altered=p;altered.dev_class=classes;
    try testing.expectError(error.NotHollowCircle,marker(&altered,lib,net));
    try allPairs(&altered,actual);
}

test "CT output markers: an explicit contrary port keeps its honoured side" {
    // This admitted caller request declines the automatic whole-stage owner.
    // Its contract is the requested real terminal, not the automatic148 parts.
    var arena=std.heap.ArenaAllocator.init(testing.allocator);defer arena.deinit();
    const a=arena.allocator();
    const text=try a.print("{s}\n*@ port p2 right\n",.{deck});
    var nl=try np.netlist.parse(a,&.{text},null);
    try testing.expectEqual(@as(usize,7),nl.hints.len);
    try testing.expectEqual(np.hints.Verb.port,nl.hints[6].verb);
    const roles=try np.guessRoles(a,&nl);
    const st=try np.schematic.structure.analyze(testing.allocator,a,&nl,roles);
    const sk=try np.schematic.skeleton.place(testing.allocator,a,&nl,roles,&st,.{});
    const lib=try support.library(testing.allocator);defer support.freeLibrary(testing.allocator,lib);
    for ([_]bool{false,true}) |compact| {
        var p=try np.place(testing.allocator,&.{.layout=.{.compact=compact,.shelf=8}},lib,&.{text},null);defer p.deinit();
        _=try native(&p,lib,false);
        const verdicts=try np.report.verdicts(a,&nl,roles,&st,&sk,&p,lib);
        try testing.expectEqual(np.hints.State.honoured,verdicts[6].state);
        const m=try marker(&p,lib,netIn(&p,"p2").?);
        try testing.expect(facing(m.at,m.from,.right));
        try support.expectConnected(&p,lib);
        try testing.expectEqual(@as(u32,0),try support.shorts(testing.allocator,&p,true));
    }
}


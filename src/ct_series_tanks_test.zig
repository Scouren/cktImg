//! L-C-L placement transaction: shifted frames, eight poses, rollback/OOM.
//! Oracle: literal source-relative terminal inequalities, unchanged whole
//! rows/coordinates on failure, and selected-path allocation-failure sweep.
//!
//! Contents: fixture/classes, actual geometry oracle, allocation probe, tests.

const std = @import("std");
const testing = std.testing;
const owner = @import("ct_series_tanks.zig");
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const library = @import("library.zig");
const skeleton = @import("skeleton.zig");
const structure = @import("structure.zig");
const pinned = @import("pinned.zig");
const netlines = @import("netlines.zig");
const Lengths = @import("canvas.zig").Lengths;
const Pt = library.Pt;

const deck = "Series transaction\n.subckt ct_inductor n1 n2 n3\n" ++
    "L1 n1 n3 1n\nL2 n3 n2 1n\n.ends\n" ++
    "XL a b vdd ct_inductor\nLS1 a c 1n\nLS2 b d 1n\nC1 c d 1p\nR1 remote 0 1k\n";

// ---- private ----

fn classes(lib: *library.Library) ![2]library.ClassId {
    _ = try lib.register(.{ .name="ct_inductor", .terminals=&.{
        .{ .name="n1", .at=.{.x=-50,.y=0}, .side=.left },
        .{ .name="n2", .at=.{.x=50,.y=0}, .side=.right },
        .{ .name="n3", .at=.{.x=0,.y=20}, .side=.down },
    }, .draw=&.{ .ln(-50,0,50,0), .ln(0,0,0,20) } });
    for ([_][]const u8{"ind","cap","res"}) |name| _ = try lib.register(.{ .name=name, .terminals=&.{
        .{ .name="a", .at=.{.x=-13,.y=9}, .side=.left },
        .{ .name="b", .at=.{.x=27,.y=9}, .side=.right },
    }, .draw=&.{.ln(-13,9,27,9)} });
    const skew = try lib.register(.{ .name="skew", .terminals=&.{
        .{ .name="a", .at=.{.x=-13,.y=12}, .side=.left },
        .{ .name="b", .at=.{.x=27,.y=9}, .side=.right },
    }, .draw=&.{.ln(-13,12,27,9)} });
    const wall = try lib.register(.{ .name="wall", .terminals=&.{
        .{ .name="a", .at=.{.x=-20,.y=0}, .side=.left },
        .{ .name="b", .at=.{.x=20,.y=0}, .side=.right },
    }, .draw=&.{.{.circle=.{.c=.zero,.r=1000}}} });
    return .{skew,wall};
}
fn actual(s: *const sch.Schematic, nl: *const netlist.Netlist, at: []const [2]f32) [9]Pt {
    const names = [_][]const u8{"xl","xl","xl","ls1","ls1","ls2","ls2","c1","c1"};
    const pins = [_]usize{0,1,2,0,1,0,1,0,1};
    var p: [9]Pt = undefined;
    for (names,pins,&p) |name,pin,*point| {
        const d = nl.device(name).?.index();
        const row = s.devices.get(d);
        point.* = Pt.round(at[d]).add(row.orient.apply(s.lib.at(row.class).terminals[pin].at).sub(row.grid));
    }
    return p;
}
fn geometry(p: [9]Pt) bool {
    const horizontal = p[0].y == p[1].y and p[0].x != p[1].x;
    const vertical = p[0].x == p[1].x and p[0].y != p[1].y;
    if (!horizontal and !vertical) return false;
    var q: [9][2]i64 = undefined;
    for (p,&q) |point,*v| v.* = if (horizontal) .{point.x,point.y} else .{point.y,point.x};
    const midpoint = q[0][0]+q[1][0];
    const row = q[0][1];
    if (2*q[2][0] != midpoint or q[2][1] == row) return false;
    const along: i64 = if (q[1][0] > q[0][0]) 1 else -1;
    const away: i64 = if (q[2][1] > row) -1 else 1;
    for (&q) |*v| v.* = .{(2*v[0]-midpoint)*along,(v[1]-row)*away};
    return q[3][0] == q[4][0] and q[5][0] == q[6][0] and q[3][1] == q[5][1] and
        q[4][1] == q[6][1] and q[7][1] == q[8][1] and q[7][0]+q[8][0] == 0 and
        q[3][0] < q[0][0] and q[0][0] < q[7][0] and q[7][0] < 0 and
        0 < q[8][0] and q[8][0] < q[1][0] and q[1][0] < q[5][0] and
        0 < q[3][1] and q[3][1] < q[4][1] and q[4][1] < q[7][1];
}
fn allocation(gpa: std.mem.Allocator, nl: *const netlist.Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) !void {
    var rows: [5]sch.DeviceInfo = undefined;
    for (&rows,0..) |*row,d| row.* = s.devices.get(d);
    var batch = owner.collect(gpa,nl,s,sk,st,ats,lines) catch |err| {
        for (rows,0..) |row,d| try testing.expectEqualDeep(row,s.devices.get(d));
        return err;
    };
    defer batch.deinit(gpa);
    try testing.expectEqual(@as(usize,1),batch.groups.items.len);
    for (rows,0..) |row,d| try testing.expectEqualDeep(row,s.devices.get(d));
}

// ---- tests ----

test "CT series transaction: shifted L frame in eight coil poses and complete rollback" {
    const gpa = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var nl = try netlist.parse(a,&.{deck},null);
    const roles = try sch.guessRoles(a,&nl);
    var lib = library.Library.init(gpa);
    defer lib.deinit();
    const bad = try classes(&lib);
    var s = try sch.initDevices(gpa,&nl,roles,&lib);
    defer s.deinit();
    for (0..s.devices.len) |d| s.devices.set(d,.{.kept=true,.driver=false,.class=s.devices.items(.class)[d],.orientation=.horizontal,.flip_x=false,.flip_y=false,.orient=.r0,.grid=.zero,.reach=@splat(0)});
    sch.settleDevices(&s,&nl.graph);
    var st = try structure.analyze(gpa,a,&nl,roles);
    var sk = try skeleton.place(gpa,a,&nl,roles,&st,.{.shelf=0});
    const mates = try a.alloc(u32,s.devices.len); @memset(mates,sch.none); st.device_mate=mates;
    st.block_kind=&.{}; st.block_devices=&.{}; st.block_start=&.{0};
    const drawn = try a.alloc(bool,s.devices.len); @memset(drawn,true); sk.drawn=drawn;
    const shelf = try a.alloc(u32,s.devices.len); @memset(shelf,0); sk.shelf=shelf;
    const ats: [5]?pinned.At = @splat(null);
    const lines = try netlines.read(a,&nl,roles,lib.unit,&.{});
    try testing.checkAllAllocationFailures(gpa,allocation,.{&nl,&s,&sk,&st,&ats,&lines});
    var batch = try owner.collect(gpa,&nl,&s,&sk,&st,&ats,&lines);
    defer batch.deinit(gpa);
    const group = batch.groups.items[0];
    // Each held member must veto before any frame mutation. The same
    // boundary on an unrelated part must not disable this owner.
    const selected = nl.device("ls1").?.index();
    const foreign = nl.device("r1").?.index();
    const selected_net = nl.net("a").?.index();
    const foreign_net = nl.net("remote").?.index();
    for ([_]bool{false,true}) |unrelated| for (0..8) |guard| {
        const d = if (unrelated) foreign else selected;
        const net = if (unrelated) foreign_net else selected_net;
        var own_st = st;
        var own_lines = lines;
        var own_ats = ats;
        const old_drawn = drawn[d];
        const old_shelf = shelf[d];
        const old_mate = mates[d];
        defer { drawn[d]=old_drawn; shelf[d]=old_shelf; mates[d]=old_mate; }
        const block = [_]u32{@intCast(d)};
        const styles = try a.dupe(netlines.Style, lines.style);
        const sides = try a.dupe(?library.Side, lines.port);
        const route = [_]netlines.Route{.{.net=@intCast(net),.pts=&.{.{.x=-90,.y=-90},.{.x=-60,.y=-90}},.via=false,.line=0}};
        switch (guard) {
            0 => drawn[d]=false,
            1 => mates[d]=@intCast(if(unrelated) d else foreign),
            2 => shelf[d]+=1,
            3 => own_st.block_devices=&block,
            4 => own_ats[d]=.{.origin=.{.x=-90,.y=-90},.orient=.r0,.line=0},
            5 => { styles[net]=.label; own_lines.style=styles; },
            6 => { sides[net]=.left; own_lines.port=sides; },
            7 => own_lines.routes=&route,
            else => unreachable,
        }
        var held_batch = try owner.collect(gpa,&nl,&s,&sk,&own_st,&own_ats,&own_lines);
        defer held_batch.deinit(gpa);
        try testing.expectEqual(@as(usize,@intFromBool(unrelated)),held_batch.groups.items.len);
    };
    var original: [5]sch.DeviceInfo = undefined;
    for (&original,0..) |*row,d| row.*=s.devices.get(d);
    const coil=nl.device("xl").?.index();
    const outside=nl.device("r1").?.index();
    for (0..8) |pose| {
        for (original,0..) |row,d| s.devices.set(d,row);
        s.devices.items(.orientation)[coil]=if(pose<4) .horizontal else .vertical;
        s.devices.items(.flip_x)[coil]=pose%2!=0; s.devices.items(.flip_y)[coil]=(pose/2)%2!=0;
        sch.settleDevice(&s,&nl.graph,coil);
        const coil_before=s.devices.get(coil);
        var positions: [5][2]f32=@splat(.{400,400}); positions[outside]=.{4000,4000};
        batch.groups.items.len=1; batch.groups.items[0]=group;
        owner.place(&s,&nl,&sk,&ats,Lengths.of(.{},lib.unit),&positions,&batch.groups);
        try testing.expectEqual(@as(usize,1),batch.groups.items.len);
        const points=actual(&s,&nl,&positions);
        try testing.expect(geometry(points));
        var mutation=points; mutation[3]=points[0]; try testing.expect(!geometry(mutation));
        try testing.expectEqualDeep(coil_before,s.devices.get(coil));
        try testing.expectEqualDeep([2]f32{400,400},positions[coil]);
        try testing.expectEqualDeep(original[outside],s.devices.get(outside));
    }
    for (0..2) |failure| {
        for (original,0..) |row,d| s.devices.set(d,row);
        var positions: [5][2]f32=@splat(.{400,400}); positions[outside]=.{4000,4000};
        const changed=if(failure==0) nl.device("c1").?.index() else outside;
        s.devices.items(.class)[changed]=bad[failure]; sch.settleDevice(&s,&nl.graph,changed);
        if(failure==1) positions[outside]=.{400,400};
        var before: [5]sch.DeviceInfo=undefined;
        for(&before,0..) |*row,d| row.*=s.devices.get(d);
        const old=positions;
        batch.groups.items.len=1; batch.groups.items[0]=group;
        owner.place(&s,&nl,&sk,&ats,Lengths.of(.{},lib.unit),&positions,&batch.groups);
        try testing.expectEqual(@as(usize,0),batch.groups.items.len);
        try testing.expectEqualDeep(old,positions);
        for(before,0..) |row,d| try testing.expectEqualDeep(row,s.devices.get(d));
    }
}

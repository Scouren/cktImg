//! Literal load-stage admission, actual-frame rollback and OOM oracles.
//! Complete named incidence is independent of placement. A successful
//! full owner is followed by one incompatible caller frame: every earlier
//! device row and coordinate must remain bit-for-bit unchanged.
//!
//! Contents: literal cards, setup/allocation helpers, then tests.

const std = @import("std");
const testing = std.testing;
const netlist = @import("netlist.zig");
const library = @import("library.zig");
const sch = @import("schematic.zig");
const structure = @import("structure.zig");
const skeleton = @import("skeleton.zig");
const pinned = @import("pinned.zig");
const netlines = @import("netlines.zig");
const loads = @import("resistor_loads.zig");
const placement = @import("resistor_load_place.zig");
const Lengths = @import("canvas.zig").Lengths;

const prefix = "Loads\n.model nn nmos\n.model pp pmos\n";
const single = "ML top top vdd vdd pp\nR1 top a 1k\nR2 top b 1k\nM1 a in1 tail 0 nn\nM2 b in2 tail 0 nn\nMT tail vb2 0 0 nn\n";
const following = "MN top2 top2 vdd vdd pp\nR3 top2 c 1k\nR4 top2 d 1k\nM3 c a tail2 0 nn\nM4 d b tail2 0 nn\nMU tail2 vb2 0 0 nn\n";

// ---- private ----

fn register(lib: *library.Library) !void {
    _ = try lib.register(.{ .name = "res", .terminals = &.{
        .{ .name = "a", .at = .{ .x = -20, .y = 0 }, .side = .left },
        .{ .name = "b", .at = .{ .x = 20, .y = 0 }, .side = .right },
    }, .draw = &.{.{ .line = .{ .a = .{ .x = -20, .y = 0 }, .b = .{ .x = 20, .y = 0 } } }} });
    for ([_][]const u8{ "nmos", "pmos" }) |name| _ = try lib.register(.{ .name = name, .terminals = &.{
        .{ .name = "d", .at = .{ .x = 20, .y = 0 }, .side = .right },
        .{ .name = "g", .at = .{ .x = 0, .y = -20 }, .side = .up },
        .{ .name = "s", .at = .{ .x = -20, .y = 0 }, .side = .left },
    }, .draw = &.{
        .{ .line = .{ .a = .{ .x = -20, .y = 0 }, .b = .{ .x = 20, .y = 0 } } },
        .{ .line = .{ .a = .{ .x = 0, .y = -20 }, .b = .zero } },
    } });
}

fn allocation(gpa: std.mem.Allocator, nl: *const netlist.Netlist, s: *sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines, paired: bool) !void {
    var before: [12]sch.DeviceInfo = undefined;
    for (before[0..s.devices.len],0..) |*row,d| row.*=s.devices.get(d);
    var batch=loads.collect(gpa,nl,s,sk,st,ats,lines) catch |err| {
        for (before[0..s.devices.len],0..) |row,d| try testing.expectEqualDeep(row,s.devices.get(d));
        return err;
    };
    defer batch.deinit(gpa);
    try testing.expectEqual(@as(usize,if(paired) 0 else 1),batch.singles.items.len);
    try testing.expectEqual(@as(usize,if(paired) 1 else 0),batch.pairs.items.len);
    for (before[0..s.devices.len],0..) |row,d| try testing.expectEqualDeep(row,s.devices.get(d));
}

// ---- tests ----

test "resistor load transaction: whole six/twelve rollback and allocation failure leave geometry intact" {
    const gpa=testing.allocator;
    for ([_]bool{false,true}) |paired| {
        var arena=std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const a=arena.allocator();
        const text=try std.mem.concat(a,u8,&.{prefix,single,if(paired) following else ""});
        var nl=try netlist.parse(a,&.{text},null);
        const roles=try sch.guessRoles(a,&nl);
        var lib=library.Library.init(gpa);
        defer lib.deinit();
        try register(&lib);
        var s=try sch.initDevices(gpa,&nl,roles,&lib);
        defer s.deinit();
        for(0..s.devices.len) |d| s.devices.set(d,.{
            .kept=true,.driver=false,.class=s.devices.items(.class)[d],
            .orientation=.horizontal,.flip_x=false,.flip_y=false,
            .orient=.r0,.grid=.zero,.reach=@splat(0),
        });
        sch.settleDevices(&s,&nl.graph);
        const st=try structure.analyze(gpa,a,&nl,roles);
        const sk=try skeleton.place(gpa,a,&nl,roles,&st,.{.shelf=0});
        const ats=try a.alloc(?pinned.At,s.devices.len);
        @memset(ats,null);
        const verdicts=try a.alloc(?@import("hints.zig").Verdict,nl.hints.len);
        @memset(verdicts,null);
        const lines=try netlines.read(a,&nl,roles,lib.unit,verdicts);
        try testing.checkAllAllocationFailures(gpa,allocation,.{&nl,&s,&sk,&st,ats,&lines,paired});
        var batch=try loads.collect(gpa,&nl,&s,&sk,&st,ats,&lines);
        defer batch.deinit(gpa);
        const at=try a.alloc([2]f32,s.devices.len);
        for (at,0..) |*p,d| p.*=.{@floatFromInt(80*d),200};
        const old=try a.alloc(sch.DeviceInfo,s.devices.len);
        for(old,0..) |*row,d| row.*=s.devices.get(d);
        const original=try a.dupe([2]f32,at);
        placement.place(&s,&nl,&sk,ats,Lengths.of(.{},lib.unit),at,&batch);
        try testing.expectEqual(@as(usize,if(paired) 0 else 1),batch.singles.items.len);
        try testing.expectEqual(@as(usize,if(paired) 1 else 0),batch.pairs.items.len);
        var moved=false;
        for(original,at) |x,y| moved=moved or x[0]!=y[0] or x[1]!=y[1];
        try testing.expect(moved);
        const base = try a.dupe(sch.DeviceInfo,old);
        for(old,0..) |row,d| s.devices.set(d,row);
        @memcpy(at,original);
        // Real registered hidden body leads do not invalidate a D/G/S
        // frame. An extra visible nonreference body lead must abstain.
        for ([_]bool{true,false}) |hidden| {
            const body = try lib.register(.{.name=if(hidden) "hidden_load_body" else "visible_load_body",.terminals=&.{
                .{.name="d",.at=.{.x=20,.y=0},.side=.right},
                .{.name="g",.at=.{.x=0,.y = -20},.side=.up},
                .{.name="s",.at=.{.x = -20,.y=0},.side=.left},
                .{.name="b",.at=.{.x=0,.y=10},.side=.down,.hidden=hidden},
            },.draw=&.{
                .{.line=.{.a=.{.x = -20,.y=0},.b=.{.x=20,.y=0}}},
                .{.line=.{.a=.{.x=0,.y = -20},.b=.zero}},
            }});
            s.devices.items(.class)[nl.device("mt").?.index()] = body;
            sch.settleDevice(&s,&nl.graph,nl.device("mt").?.index());
            var body_batch=try loads.collect(gpa,&nl,&s,&sk,&st,ats,&lines);
            defer body_batch.deinit(gpa);
            placement.place(&s,&nl,&sk,ats,Lengths.of(.{},lib.unit),at,&body_batch);
            try testing.expectEqual(@as(usize,@intFromBool(hidden)),body_batch.singles.items.len+body_batch.pairs.items.len);
            for(base,0..) |row,i| s.devices.set(i,row);
            @memcpy(at,original);
        }
        const bad=try lib.register(.{.name="bad_load_gate",.terminals=&.{
            .{.name="d",.at=.{.x=20,.y=0},.side=.right},
            .{.name="g",.at=.{.x=0,.y=0},.side=.up},
            .{.name="s",.at=.{.x = -20,.y=0},.side=.left},
        },.draw=&.{.{.line=.{.a=.{.x = -20,.y=0},.b=.{.x=20,.y=0}}}}});
        // The last tail fails only after the earlier owner rows were posed.
        const d=nl.device(if(paired) "mu" else "mt").?.index();
        s.devices.items(.class)[d]=bad;
        sch.settleDevice(&s,&nl.graph,d);
        for(old,0..) |*row,i| row.*=s.devices.get(i);
        placement.place(&s,&nl,&sk,ats,Lengths.of(.{},lib.unit),at,&batch);
        try testing.expectEqual(@as(usize,0),batch.singles.items.len+batch.pairs.items.len);
        for(old,0..) |row,i| try testing.expectEqualDeep(row,s.devices.get(i));
        try testing.expectEqualDeep(original,at);
        // A valid class and representable origin can have an actual lead
        // outside i32. Widen before adding, then abstain without mutation.
        for(base,0..) |row,i| s.devices.set(i,row);
        const wide = try lib.register(.{.name="wide_load_input",.terminals=&.{
            .{.name="d",.at=.{.x=200,.y=0},.side=.right},
            .{.name="g",.at=.{.x=0,.y = -200},.side=.up},
            .{.name="s",.at=.{.x = -200,.y=0},.side=.left},
        },.draw=&.{.{.line=.{.a=.{.x = -200,.y=0},.b=.{.x=200,.y=0}}}}});
        const input = nl.device("m1").?.index();
        s.devices.items(.class)[input] = wide;
        s.devices.items(.orientation)[input] = .horizontal;
        s.devices.items(.flip_x)[input] = false;
        s.devices.items(.flip_y)[input] = false;
        sch.settleDevice(&s,&nl.graph,input);
        at[input] = .{2147483520,200};
        const extreme = try a.dupe([2]f32,at);
        for(old,0..) |*row,i| row.*=s.devices.get(i);
        var extreme_batch=try loads.collect(gpa,&nl,&s,&sk,&st,ats,&lines);
        defer extreme_batch.deinit(gpa);
        placement.place(&s,&nl,&sk,ats,Lengths.of(.{},lib.unit),at,&extreme_batch);
        try testing.expectEqual(@as(usize,0),extreme_batch.singles.items.len+extreme_batch.pairs.items.len);
        for(old,0..) |row,i| try testing.expectEqualDeep(row,s.devices.get(i));
        try testing.expectEqualDeep(extreme,at);
        @memcpy(at,original);
        // An unsupported input must abstain before reading its first tip.
        for(base,0..) |row,i| s.devices.set(i,row);
        try testing.expectError(error.NoTerminals,lib.register(.{.name="empty_load_input",.terminals=&.{},.draw=&.{}}));
        const empty = try lib.register(.{.name="one_load_input",.terminals=&.{.{.name="d",.at=.zero,.side=.right}},.draw=&.{}});
        s.devices.items(.class)[nl.device("m1").?.index()] = empty;
        for ([_]bool{false,true}) |malformed| {
            // The second case deliberately bypasses register's boundary.
            // Neither an unsupported nor missing lead may be read blindly.
            if (malformed) lib.classes.items[@backingInt(empty)].terminals=&.{};
            for(old,0..) |*row,i| row.*=s.devices.get(i);
            var unsupported = try loads.collect(gpa,&nl,&s,&sk,&st,ats,&lines);
            defer unsupported.deinit(gpa);
            placement.place(&s,&nl,&sk,ats,Lengths.of(.{},lib.unit),at,&unsupported);
            try testing.expectEqual(@as(usize,0),unsupported.singles.items.len+unsupported.pairs.items.len);
            for(old,0..) |row,i| try testing.expectEqualDeep(row,s.devices.get(i));
            try testing.expectEqualDeep(original,at);
        }
    }
}

test "resistor load admission: raw competitors and admitted owner requests abstain atomically" {
    const gpa=testing.allocator;
    const rows=[_]struct{text:[]const u8,single:usize=0,paired:usize=0}{
        .{.text="",.single=1,.paired=1},
        .{.text="MOTHER a other 0 0 unknown\n"},
        .{.text="RPAR top a 2k\n"},
        .{.text="MLOAD another another vdd vdd pp\nRA another a 1k\nRB another b 1k\n"},
        .{.text="*@ cell m1 -2 3\n"},
        .{.text="*@ grouping off\n"},
        .{.text="*@ symmetry off\n"},
        .{.text="*@ face mt g left\n"},
        .{.text="*@ face missing g left\n",.single=1,.paired=1},
        // Absent downstream names are rejected in the single deck. When
        // present, a request on that stage must reject the whole pair.
        .{.text="*@ cell m3 -2 3\n",.single=1},
        .{.text="*@ face mu g left\n",.single=1},
        .{.text="*@ wire top2\n",.single=1},
    };
    for([_]bool{false,true}) |paired| for(rows) |row| {
        var arena=std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const a=arena.allocator();
        const text=try std.mem.concat(a,u8,&.{prefix,single,if(paired) following else "",row.text});
        var nl=try netlist.parse(a,&.{text},null);
        const roles=try sch.guessRoles(a,&nl);
        var lib=library.Library.init(gpa);
        defer lib.deinit();
        try register(&lib);
        var s=try sch.initDevices(gpa,&nl,roles,&lib);
        defer s.deinit();
        for(0..s.devices.len) |d| s.devices.set(d,.{
            .kept=true,.driver=false,.class=s.devices.items(.class)[d],
            .orientation=.horizontal,.flip_x=false,.flip_y=false,
            .orient=.r0,.grid=.zero,.reach=@splat(0),
        });
        sch.settleDevices(&s,&nl.graph);
        const st=try structure.analyze(gpa,a,&nl,roles);
        const sk=try skeleton.place(gpa,a,&nl,roles,&st,.{.shelf=0});
        const ats=try a.alloc(?pinned.At,s.devices.len);
        @memset(ats,null);
        const verdicts=try a.alloc(?@import("hints.zig").Verdict,nl.hints.len);
        @memset(verdicts,null);
        const lines=try netlines.read(a,&nl,roles,lib.unit,verdicts);
        var batch=try loads.collect(gpa,&nl,&s,&sk,&st,ats,&lines);
        defer batch.deinit(gpa);
        errdefer std.debug.print("load admission extra: {s}\n",.{row.text});
        try testing.expectEqual(if(paired) @as(usize,0) else row.single,batch.singles.items.len);
        try testing.expectEqual(if(paired) row.paired else @as(usize,0),batch.pairs.items.len);
    };
}

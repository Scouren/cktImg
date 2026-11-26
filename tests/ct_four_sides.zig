//! Whole AG1153: two L-C-L tanks inside four transistor groups.
//! Oracle: independently assigned actual SVG endpoints and physical ink,
//! R/series-whole-stage.json (one figure;72 visible leads,148 same-net pairs).
//! Source substrate bindings remain present; their absent frames are not guessed.
//! This future suite is intentionally unimported until the owner is reviewed.
//!
//! Contents: frozen source contracts, actual frame reader, geometry, tests.

const std=@import("std");
const testing=std.testing;
const np=@import("NetlistParser");
const support=@import("support.zig");
const ink=@import("wire_ink.zig");
const deck=@embedFile("ct_series_tanks_fixture.sp");
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

// ---- private ----

fn point(f: Frame,name:[]const u8,pin:u8) np.Pt {
    for(endpoints,0..) |e,i| if(e.index==pin and std.mem.eql(u8,e.card,name)) return f[i];
    unreachable;
}
fn index(name:[]const u8,pin:u8) usize {
    for(endpoints,0..) |e,i| if(e.index==pin and std.mem.eql(u8,e.card,name)) return i;
    unreachable;
}
fn geometry(f:Frame) bool {
    const a=point(f,"xl1",0); const b=point(f,"xl1",1); const tap=point(f,"xl1",2);
    const c=point(f,"xl2",0); const d=point(f,"xl2",1); const tap2=point(f,"xl2",2);
    const axis2=@as(i64,a.x)+b.x;
    if(!(a.x<b.x and c.x<d.x and a.y==b.y and c.y==d.y and axis2==@as(i64,c.x)+d.x)) return false;
    if(!(2*@as(i64,tap.x)==axis2 and 2*@as(i64,tap2.x)==axis2 and a.y<tap.y and tap.y<tap2.y and tap2.y<c.y)) return false;
    // Literal semantic passive ends; distances are not prescribed.
    const branches=[2][8]usize{
        .{index("xl1",0),index("xl1",1),index("ls1",1),index("ls1",0),index("ls2",1),index("ls2",0),index("c1",1),index("c1",0)},
        .{index("xl2",0),index("xl2",1),index("ls3",0),index("ls3",1),index("ls4",0),index("ls4",1),index("c2",1),index("c2",0)},
    };
    for(branches,0..) |ii,g| {
        const l=f[ii[2]];const lf=f[ii[3]];const r=f[ii[4]];const rf=f[ii[5]];const cl=f[ii[6]];const cr=f[ii[7]];
        if(!(l.x==lf.x and r.x==rf.x and l.y==r.y and lf.y==rf.y and cl.y==cr.y)) return false;
        if(!(l.x<f[ii[0]].x and f[ii[0]].x<cl.x and cl.x<cr.x and cr.x<f[ii[1]].x and f[ii[1]].x<r.x and @as(i64,cl.x)+cr.x==axis2)) return false;
        if(g==0) {if(!(cl.y<lf.y and lf.y<l.y and l.y<f[ii[0]].y)) return false;}
        else {if(!(f[ii[0]].y<l.y and l.y<lf.y and lf.y<cl.y)) return false;}
    }
    const ends=[2][5][]const u8{.{"m10","m12","m13","m11","m14"},.{"m5","m7","m8","m6","m9"}};
    for(ends,0..) |ms,g| {
        const ds=point(f,ms[0],0).y;const gs=point(f,ms[0],1).y;const ss=point(f,ms[0],2).y;
        for(ms[0..4],0..) |m,i| {
            const drain=point(f,m,0);const gate=point(f,m,1);const src=point(f,m,2);
            if(!(drain.x==src.x and drain.y==ds and gate.y==gs and src.y==ss)) return false;
            if(g==0) {if(!(ss<gs and gs<ds)) return false;} else {if(!(ds<gs and gs<ss)) return false;}
            if((gate.x<drain.x)!=(i==0 or i==2)) return false;
            if(i>0 and point(f,ms[i-1],0).x>=drain.x) return false;
        }
        if(@as(i64,point(f,ms[0],0).x)+point(f,ms[3],0).x!=axis2 or @as(i64,point(f,ms[1],0).x)+point(f,ms[2],0).x!=axis2) return false;
        const td=point(f,ms[4],0);const tg=point(f,ms[4],1);const ts=point(f,ms[4],2);
        if(!(td.y==ss and td.x==ts.x and 2*@as(i64,td.x)==axis2 and tg.x<td.x)) return false;
        if(g==0) {if(!(ts.y<tg.y and tg.y<td.y and ds<point(f,"c1",0).y)) return false;}
        else {if(!(td.y<tg.y and tg.y<ts.y and point(f,"c2",0).y<ds)) return false;}
    }
    const sides=[2][4][]const u8{.{"m15","m16","m17","m18"},.{"m19","m20","m21","m22"}};
    for(sides,0..) |ms,g| {
        const da=point(f,ms[0],0);const db=point(f,ms[1],0);const ga=point(f,ms[0],1);const gb=point(f,ms[1],1);const sa=point(f,ms[0],2);const sb=point(f,ms[1],2);
        if(!(da.x==sa.x and db.x==sb.x and da.y==db.y and ga.y==gb.y and sa.y==sb.y and a.y<da.y and da.y<ga.y and ga.y<sa.y and sa.y<c.y)) return false;
        if(g==0) {if(!(db.x<gb.x and gb.x<ga.x and ga.x<da.x and da.x<a.x)) return false;}
        else {if(!(b.x<da.x and da.x<ga.x and ga.x<gb.x and gb.x<db.x)) return false;}
        const center2=@as(i64,da.x)+db.x;
        const td=point(f,ms[2],0);const tg=point(f,ms[2],1);const ts=point(f,ms[2],2);
        if(!(2*@as(i64,td.x)==center2 and td.x==ts.x and td.y==sa.y and td.y<tg.y and tg.y<ts.y)) return false;
        if((tg.x<td.x)!=(g==0)) return false;
        const bd=point(f,ms[3],0);const bg=point(f,ms[3],1);const bs=point(f,ms[3],2);
        if(!(bd.y==bs.y and bg.y<bd.y and bd.y<a.y and @as(i64,bd.x)+bs.x==center2 and 2*@as(i64,bg.x)==center2)) return false;
        if((bd.x>bs.x)!=(g==0)) return false;
    }
    const mirrors=[8][2][]const u8{.{"m10","m11"},.{"m12","m13"},.{"m5","m6"},.{"m7","m8"},.{"m15","m19"},.{"m16","m20"},.{"m17","m21"},.{"m18","m22"}};
    for(mirrors) |pair| for(0..3) |pin| {
        const l=point(f,pair[0],@intCast(pin));const r=point(f,pair[1],@intCast(pin));
        if(l.y!=r.y or @as(i64,l.x)+r.x!=axis2) return false;
    };
    return true;
}
fn native(p:*const np.Placed,lib:*const np.Library) !Actual {
    var named:usize=0;var raw:usize=0;
    for(p.dev_name) |name| if(name.len!=0) {named+=1;};
    try testing.expectEqual(contracts.len,named);
    for(contracts) |contract| {
        const d=np.checks.deviceIn(p,contract.card) orelse return error.MissingCard;
        const lo,const hi=p.pinRange(d);try testing.expectEqual(contract.nets.len,hi-lo);
        for(contract.nets,lo..) |net,pin| {try testing.expectEqualStrings(net,p.net_name[p.pin_net[pin]]);raw+=1;}
    }
    try testing.expectEqual(@as(usize,90),raw);
    var out:Actual=undefined;
    for(endpoints,0..) |e,i| {
        const d=np.checks.deviceIn(p,e.card).?;const lo,const hi=p.pinRange(d);
        try testing.expect(lo+e.index<hi);
        const cls=lib.at(p.dev_class[d]);try testing.expect(e.index<cls.terminals.len and !cls.terminals[e.index].hidden);
        const pin=lo+e.index;try testing.expectEqualStrings(e.net,p.net_name[p.pin_net[pin]]);
        const actual=p.dev_pos[d].add(p.dev_orient[d].apply(cls.terminals[e.index].at));
        try testing.expectEqualDeep(actual,p.pin_xy[pin]);out.points[i]=actual;out.pins[i]=pin;
    }
    return out;
}

// ---- tests ----

test "CT four sides: literal full source frame and mutations define the observed case" {
    var f:Frame=undefined;for(endpoints,&f) |e,*p| p.*=e.source;
    try testing.expect(geometry(f));
    var shifted=f;for(&shifted) |*p| p.*=.{.x=3*p.x+37,.y=3*p.y-91};try testing.expect(geometry(shifted));
    for([_]struct {name:[]const u8,pin:u8,delta:np.Pt}{
        .{.name="xl2",.pin=2,.delta=.{.x=0,.y=40}},
        .{.name="m14",.pin=1,.delta=.{.x=60,.y=0}},
        .{.name="m18",.pin=1,.delta=.{.x=0,.y=60}},
        .{.name="m12",.pin=2,.delta=.{.x=0,.y=80}},
        .{.name="m20",.pin=0,.delta=.{.x=10,.y=0}},
        .{.name="c1",.pin=0,.delta=.{.x=10,.y=0}},
    }) |mutation| {var bad=f;const i=index(mutation.name,mutation.pin);bad[i]=bad[i].add(mutation.delta);try testing.expect(!geometry(bad));}
    var pairs:usize=0;var joined:usize=0;
    for(endpoints,0..) |a,i| for(endpoints[i+1..]) |b| if(std.mem.eql(u8,a.net,b.net)) {pairs+=1;joined+=@intFromBool(a.part==b.part);};
    try testing.expectEqual(@as(usize,148),pairs);try testing.expectEqual(@as(usize,81),joined);
}

test "CT four sides: complete source world frame preserves all90 ordered bindings" {
    const lib=try support.library(testing.allocator);defer support.freeLibrary(testing.allocator,lib);
    for([_]bool{false,true}) |compact| {
        var p=try np.place(testing.allocator,&.{.layout=.{.compact=compact,.shelf=8}},lib,&.{deck},null);defer p.deinit();
        errdefer std.debug.print("whole source frame compact={}\n",.{compact});
        const actual=try native(&p,lib);try testing.expect(geometry(actual.points));
        try support.expectConnected(&p,lib);try testing.expectEqual(@as(u32,0),try support.shorts(testing.allocator,&p,true));
    }
}

test "CT four sides: all148 actual source physical pair expectations remain immutable" {
    const lib=try support.library(testing.allocator);defer support.freeLibrary(testing.allocator,lib);
    for([_]bool{false,true}) |compact| {
        var p=try np.place(testing.allocator,&.{.layout=.{.compact=compact,.shelf=8}},lib,&.{deck},null);defer p.deinit();
        const actual=try native(&p,lib);var checked:usize=0;
        for(endpoints,0..) |a,i| for(endpoints[i+1..],i+1..) |b,j| {
            if(!std.mem.eql(u8,a.net,b.net)) continue;
            const expected=a.part==b.part;
            const observed=try ink.connected(testing.allocator,&p,&.{actual.pins[i],actual.pins[j]});
            errdefer std.debug.print("whole source ink compact={} {s}:{s}.{}--{s}.{} expected={} observed={}\n",.{compact,a.net,a.card,a.index,b.card,b.index,expected,observed});
            try testing.expectEqual(expected,observed);checked+=1;
        };
        try testing.expectEqual(@as(usize,148),checked);
    }
}

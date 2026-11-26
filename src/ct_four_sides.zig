//! Complete paired CT/LCL/four-MOS-bank scene -> one cold placement owner.
//!
//! Human Rules:
//! - ct_four_sides.1 (bounded observation) The full 2936-deck census has one
//!   complete 26-member case. Directed bypass channels distinguish upper
//!   and lower tanks. Count all raw candidates and all90 pin incidences
//!   before known-NMOS, rail, visibility or caller eligibility. No name,
//!   value or figure ID selects it. Source: docs/research/ct-four-sides.md;
//!   source geometry and all148 physical partitions are independent tests.
//! - ct_four_sides.2 (boundary) Exact mates, admitted member requests,
//!   external block members and touched-net styles/ports/routes abstain.
//!   Fully contained automatic blocks remain; ordinary first-net ordering
//!   and rail representation retain their existing owners. `collect`
//! - ct_four_sides.3 (choice) Protect the whole semantic column span from
//!   a shelf cut only. A later unsupported actual frame still declines;
//!   there is no unsafe partial LCL fallback or row-gap reservation. `spans`
//!
//! Data: borrowed CSR/roles/admitted requests in; one cold [26]EdgeId
//! certificate out (104 bytes, all handles consumed together per phase).
//! The one-scene source scope admits exactly one raw candidate; no flags,
//! nets or frames are retained. Caller owns two buffers for one draw;
//! allocation precedes mutation. Recognition is outside cut-cost/routing
//! loops. No hot-path, runtime-residue or performance claim is made.
//!
//! Contents: Group, Batch, Batch.deinit, collect, spans, ports, binding; private.

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const netlist = @import("netlist.zig");
const sch = @import("schematic.zig");
const skeleton = @import("skeleton.zig");
const structure = @import("structure.zig");
const pinned = @import("pinned.zig");
const netlines = @import("netlines.zig");
const blocks = @import("block_symbols.zig");
const placement = @import("ct_four_place.zig");
const Netlist = netlist.Netlist;
const EdgeId = netlist.EdgeId;
const VertexId = netlist.VertexId;

/// Two CTs; four near-ordered Ls; two Cs; top/bottom cross,cross,shunt,
/// shunt,tail banks; left/right inner,outer,tail,bypass side banks.
pub const Group = [26]EdgeId;

/// Caller-owned candidates/successes and the derived fixed order capacity.
pub const Batch = struct {
    groups: std.ArrayList(Group),
    coordinates: [][2]i32,

    /// Releases both buffers with collect's allocator.
    pub fn deinit(self: *Batch, gpa: Allocator) void {
        self.groups.deinit(gpa);
        gpa.free(self.coordinates);
        self.* = undefined;
    }
};

const missing: EdgeId = .from(sch.none);
comptime { assert(@sizeOf(Group) == 104); }

/// Collects the complete raw unique scene with original admitted requests.
/// Arrays span nl; allocation changes no rows. Unrelated requests survive.
pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) Allocator.Error!Batch {
    assert(ats.len == nl.graph.edgeCount() and sk.drawn.len == ats.len);
    assert(st.device_mate.len == ats.len and lines.style.len == nl.graph.vertexCount());
    var groups: std.ArrayList(Group) = .empty;
    errdefer groups.deinit(gpa);
    if (find(nl, s.roles)) |group| eligible: {
        for (group) |edge| {
            const d = edge.index();
            if (!sk.drawn[d] or ats[d] != null or st.device_mate[d] != sch.none or held(nl, sk, st, edge)) break :eligible;
            if (nl.defOf(edge)) |def| for (def.sides) |side| if (side != null) break :eligible;
            for (nl.graph.members(edge)) |net| {
                if (lines.style[net.index()] != .auto or lines.port[net.index()] != null) break :eligible;
                for (lines.routes) |route| if (route.net == net.index()) break :eligible;
            }
        }
        for (0..st.block_kind.len) |i| {
            const members = st.block_devices[st.block_start[i]..st.block_start[i+1]];
            var selected: usize = 0;
            for (members) |d| selected += @intFromBool(contains(group, d));
            if (selected != 0 and selected != members.len) break :eligible;
        }
        try groups.append(gpa, group);
    }
    const coordinates = try gpa.alloc([2]i32, placement.order_capacity * groups.items.len);
    return .{ .groups = groups, .coordinates = coordinates };
}

/// Adds one cold whole-stage span before cut-cost scans. Caller frees the
/// owned result; an empty result leaves previous borrowed and unchanged.
pub fn spans(gpa: Allocator, nl: *const Netlist, roles: []const sch.Role, drawn: []const bool, x: []const i32, previous: []const [2]i32) Allocator.Error!std.ArrayList([2]i32) {
    assert(x.len == nl.graph.edgeCount() and drawn.len == x.len);
    assert(roles.len == nl.graph.vertexCount());
    var out: std.ArrayList([2]i32) = .empty;
    errdefer out.deinit(gpa);
    const group = find(nl, roles) orelse return out;
    var lo = x[group[0].index()];
    var hi = lo;
    for (group) |edge| {
        if (!drawn[edge.index()]) return out;
        lo = @min(lo,x[edge.index()]); hi = @max(hi,x[edge.index()]);
    }
    try out.ensureTotalCapacity(gpa, previous.len+1);
    out.appendSliceAssumeCapacity(previous);
    out.appendAssumeCapacity(.{lo,hi});
    return out;
}

/// Resolves exact complete CT roles in declared-port order; wrong arity
/// declines before any class or instance array is indexed.
pub fn ports(nl: *const Netlist, edge: EdgeId) ?[3]u2 {
    const def = nl.defOf(edge) orelse return null;
    if (blocks.identify(def.name,def.ports) != .center_tap or nl.graph.members(edge).len != 3) return null;
    var out: [3]u2 = undefined;
    for (def.ports,0..) |name,i| for ([_][]const u8{"n1","n2","n3"},0..) |want,j| if (std.ascii.eqlIgnoreCase(name,want)) { out[j]=@intCast(i); };
    return out;
}

/// Actual member-local semantic pin index. CT ends follow directed bypass
/// connectivity; L pins are near/far, C pins left/right, MOS pins D/G/S.
pub fn binding(nl: *const Netlist, group: Group, member: usize, role: usize) usize {
    assert(member < group.len and role < 3);
    if (member >= 8) return role;
    const side: usize = if (member < 2) 0 else if (member < 6) (member-2)%2 else 0;
    const tank_index: usize = if (member < 2) member else if (member < 6) (member-2)/2 else member-6;
    const cp = ports(nl,group[tank_index]).?;
    if (member < 2 and role == 2) return cp[2];
    const coil = nl.graph.members(group[tank_index]);
    // Bottom declaration order is independent; resolve by actual net.
    const outer = if (tank_index == 0) coil[cp[side]] else nl.graph.members(group[18+4*side])[1];
    if (member < 2) {
        const net = if (member == 0) coil[cp[role]] else nl.graph.members(group[18+4*role])[1];
        for (coil,0..) |n,i| if (n==net) return i;
        unreachable;
    }
    const p = nl.graph.members(group[member]);
    if (member < 6) return @intFromBool(p[0]!=outer) ^ role;
    const far_net = nl.graph.members(group[8+5*tank_index])[0];
    return @intFromBool(p[0]!=far_net) ^ role;
}

// ---- private ----

fn contains(group: Group, d: usize) bool { for (group) |edge| if (edge.index()==d) return true; return false; }
fn held(nl: *const Netlist, sk: *const skeleton.Skeleton, st: *const structure.Structure, edge: EdgeId) bool {
    for (nl.hints,sk.verdicts,st.verdicts) |hint,sv,tv| {
        const v = sv orelse tv orelse continue;
        if (v.state != .honoured and v.state != .relaxed) continue;
        switch (hint.verb) {
            .off,.symmetry_off,.axis => return true,
            .pair,.mirror,.bank,.stack,.cross,.nogroup,.symmetric,.row,.above,.order,.cell,.face,.upright,.bridge,.at => {},
            else => continue,
        }
        for (hint.args) |name| if ((nl.device(name) orelse continue)==edge) return true;
    }
    return false;
}
fn same(p: []const VertexId,a: VertexId,b: VertexId) bool { return p.len==2 and ((p[0]==a and p[1]==b) or (p[0]==b and p[1]==a)); }
fn tank(nl: *const Netlist, coil: EdgeId) ?[4]EdgeId {
    const c=&nl.graph;const cp=ports(nl,coil) orelse return null;const p=c.members(coil);
    const outer=[2]VertexId{p[cp[0]],p[cp[1]]};var out=[4]EdgeId{coil,missing,missing,missing};
    var rivals:usize=0;
    for(c.edges.items(.kind),0..) |kind,d| {
        if(kind!=.subckt) continue;
        const op=ports(nl,.from(d)) orelse continue;const q=c.members(.from(d));
        if((q[op[0]]==outer[0] and q[op[1]]==outer[1]) or (q[op[0]]==outer[1] and q[op[1]]==outer[0])) rivals+=1;
    }
    if(rivals!=1) return null;
    var far_nets:[2]VertexId=undefined;
    for(outer,0..) |net,i| {
        var count:usize=0;
        for(c.incident(net)) |e| if(c.edges.items(.kind)[e.index()]==.inductor) { count+=1;out[i+1]=e; };
        if(count!=1) return null;
        const q=c.members(out[i+1]);if(q.len!=2 or q[0]==q[1]) return null;
        far_nets[i]=if(q[0]==net) q[1] else q[0];
    }
    const nets=[_]VertexId{outer[0],outer[1],far_nets[0],far_nets[1],p[cp[2]]};
    for(nets,0..) |net,i| for(nets[0..i]) |old| if(net==old) return null;
    var count:usize=0;
    for(c.edges.items(.kind),0..) |kind,d| if(kind==.capacitor and same(c.members(.from(d)),far_nets[0],far_nets[1])) {count+=1;out[3]=.from(d);};
    return if(count==1) out else null;
}
fn mos(nl: *const Netlist,e: EdgeId) ?[]const VertexId {
    if(nl.graph.edges.items(.kind)[e.index()]!=.mosfet) return null;
    const p=nl.graph.members(e);return if(p.len==4) p else null;
}
fn unique(nl: *const Netlist,d: VertexId,g: ?VertexId,s: ?VertexId,b: ?VertexId) ?EdgeId {
    var found: ?EdgeId=null;
    for(nl.graph.edges.items(.kind),0..) |_,i| {
        const edge=EdgeId.from(i);const p=mos(nl,edge) orelse continue;
        if(p[0]!=d or (g!=null and p[1]!=g.?) or (s!=null and p[2]!=s.?) or (b!=null and p[3]!=b.?)) continue;
        if(found!=null) return null;
        found=edge;
    }
    return found;
}
fn five(nl: *const Netlist,a: VertexId,b: VertexId) ?[5]EdgeId {
    var forward:[2]EdgeId=undefined;var count:usize=0;
    for(nl.graph.edges.items(.kind),0..) |_,d| {
        const e=EdgeId.from(d);const p=mos(nl,e) orelse continue;
        if(p[0]!=a or p[1]!=b) continue;
        if(count==2) return null;forward[count]=e;count+=1;
    }
    if(count!=2) return null;
    const p=nl.graph.members(forward[0]);const q=nl.graph.members(forward[1]);
    if(p[3]!=q[3] or p[2]==q[2] or (p[2]!=p[3] and q[2]!=q[3])) return null;
    const cross=if(p[2]!=p[3]) forward[0] else forward[1];
    const shunt=if(p[2]==p[3]) forward[0] else forward[1];
    const common=nl.graph.members(cross)[2];const ground=p[3];
    const other=unique(nl,b,a,common,ground) orelse return null;
    const outer=unique(nl,b,a,ground,ground) orelse return null;
    const tail=unique(nl,common,null,ground,ground) orelse return null;
    return .{cross,other,shunt,outer,tail};
}
fn four(nl: *const Netlist,a: VertexId,b: VertexId) ?[4]EdgeId {
    const first=unique(nl,a,b,null,null) orelse return null;
    const p=nl.graph.members(first);
    const second=unique(nl,b,a,p[2],p[3]) orelse return null;
    const tail=unique(nl,p[2],null,p[3],p[3]) orelse return null;
    const bypass=unique(nl,a,null,b,p[3]) orelse return null;
    return .{first,second,tail,bypass};
}
fn far(nl: *const Netlist,t: [4]EdgeId,side: usize) VertexId {
    const outer=nl.graph.members(t[0])[ports(nl,t[0]).?[side]];const p=nl.graph.members(t[side+1]);
    return if(p[0]==outer) p[1] else p[0];
}
fn candidate(nl: *const Netlist,a: [4]EdgeId,b: [4]EdgeId,swap: bool) ?Group {
    const c=&nl.graph;const ap=ports(nl,a[0]).?;const bp=ports(nl,b[0]).?;
    const av=c.members(a[0]);const bv=c.members(b[0]);if(av[ap[2]]!=bv[bp[2]]) return null;
    const ea=five(nl,far(nl,a,0),far(nl,a,1)) orelse return null;
    const eb=five(nl,far(nl,b,@intFromBool(swap)),far(nl,b,@intFromBool(!swap))) orelse return null;
    const l=four(nl,av[ap[0]],bv[bp[@intFromBool(swap)]]) orelse return null;
    const r=four(nl,av[ap[1]],bv[bp[@intFromBool(!swap)]]) orelse return null;
    const ground=c.members(ea[0])[3];const low=c.members(ea[4])[1];const high=c.members(l[2])[1];
    if(c.members(eb[0])[3]!=ground or c.members(l[0])[3]!=ground or c.members(r[0])[3]!=ground or
        c.members(eb[4])[1]!=low or c.members(l[3])[1]!=low or c.members(r[3])[1]!=low or c.members(r[2])[1]!=high) return null;
    const group: Group=[_]EdgeId{a[0],b[0],a[1],a[2],b[1+@as(usize,@intFromBool(swap))],b[1+@as(usize,@intFromBool(!swap))],a[3],b[3]} ++ ea ++ eb ++ l ++ r;
    for(group,0..) |e,i| for(group[0..i]) |old| if(e==old) return null;
    const nets=[_]VertexId{av[ap[0]],av[ap[1]],bv[bp[0]],bv[bp[1]],far(nl,a,0),far(nl,a,1),far(nl,b,0),far(nl,b,1),c.members(ea[0])[2],c.members(eb[0])[2],c.members(l[0])[2],c.members(r[0])[2],av[ap[2]],ground,low,high};
    const expected=[_]usize{5,5,5,5,6,6,6,6,3,3,3,3,2,26,4,2};
    for(nets,expected,0..) |net,n,i| {
        for(nets[0..i]) |old| if(net==old) return null;
        const incidence=c.incident(net);if(incidence.len!=n) return null;
        for(incidence) |e| if(!contains(group,e.index())) return null;
    }
    return group;
}
fn find(nl: *const Netlist, roles: []const sch.Role) ?Group {
    var result: ?Group=null;
    for(nl.graph.edges.items(.kind),0..) |kind,d| {
        if(kind!=.subckt) continue;
        const a=tank(nl,.from(d)) orelse continue;
        for(nl.graph.edges.items(.kind),0..) |other,e| {
            if(other!=.subckt or e==d) continue;
            const b=tank(nl,.from(e)) orelse continue;
            for([_]bool{false,true}) |swap| if(candidate(nl,a,b,swap)) |group| {
                if(result!=null) return null;result=group;
            };
        }
    }
    const group=result orelse return null;
    for(group[8..]) |edge| if(!std.mem.eql(u8,nl.modelType(edge) orelse return null,"nmos")) return null;
    const supply=nl.graph.members(group[0])[ports(nl,group[0]).?[2]];
    const ground=nl.graph.members(group[8])[3];
    if(roles[supply.index()]!=.supply or roles[ground.index()]!=.sink) return null;
    for(group) |e| for(nl.graph.members(e)) |net| if(net!=supply and net!=ground and roles[net.index()].isRail()) return null;
    return group;
}

// ---- tests ----

test { _ = @import("ct_four_sides_test.zig"); }

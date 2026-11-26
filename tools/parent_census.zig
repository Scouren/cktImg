//! Read-only diagnostic for a selected native cell. Emits one sparse JSON record per source.
//!
//! Contents:
//! - `pub fn main(init: std.process.Init) !void`

const std = @import("std");
const np = @import("NetlistParser");
const native = @import("json.zig");
const J = std.json.Stringify;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.MissingInput;
    var buf: [65536]u8 = undefined;
    var sw = std.Io.File.stdout().writerStreaming(init.io, &buf);
    for (args[1..]) |path| {
        var scratch = std.heap.ArenaAllocator.init(init.gpa);
        defer scratch.deinit();
        const a = scratch.allocator();
        const raw = try std.Io.Dir.cwd().readFileAlloc(init.io, path, a, .limited(1 << 22));
        var diag: np.netlist.Diagnostic = .{};
        const sources = try native.deckSources(init.gpa, a, null, path, raw, &diag);
        var nl = try np.netlist.parse(init.gpa, sources, &diag);
        defer nl.deinit(init.gpa);
        const ctx = try np.parent_context.bind(a, raw, &nl, &np.parent_context.standard_rails);
        const r = try np.local_parents.collect(a, ctx, .{});
        var j = J{ .writer = &sw.interface };
        try write(&j, path, &nl, r);
        const source_regions = try np.source_regions.collect(a, raw, &nl);
        try j.objectField("source_region_scope");
        try j.write(@tagName(source_regions.scope));
        try j.objectField("source_regions");
        try j.beginArray();
        for (source_regions.regions) |region| {
            try j.beginObject();
            try j.objectField("disposition");
            try j.write(@tagName(region.disposition));
            try j.objectField("members");
            try edgeNames(&j, &nl, region.members);
            try j.objectField("owned");
            try edgeNames(&j, &nl, region.owned);
            try j.objectField("attachment_cards");
            try j.beginArray();
            for (region.owned) |e| {
                if (std.mem.indexOfScalar(np.netlist.EdgeId, region.members, e) != null) continue;
                try j.beginObject();
                try j.objectField("device");
                try j.write(nl.graph.edges.items(.name)[e.index()]);
                try j.objectField("ordered_nets");
                try j.beginArray();
                for (nl.graph.members(e)) |n| try j.write(nl.graph.vertices.items(.name)[n.index()]);
                try j.endArray();
                try j.objectField("parameters");
                try j.write(nl.params(e));
                try j.endObject();
            }
            try j.endArray();
            try j.objectField("incidence");
            try j.beginArray();
            for (region.incidence) |hit| {
                try j.beginArray();
                try j.write(nl.graph.edges.items(.name)[hit.device.index()]);
                try j.write(hit.terminal);
                try j.write(nl.graph.vertices.items(.name)[hit.net.index()]);
                try j.endArray();
            }
            try j.endArray();
            try j.endObject();
        }
        try j.endArray();
        try j.objectField("common_control_stages");
        try j.beginArray();
        for (try np.parent_stages.collect(a, ctx, r)) |stage| {
            try j.beginArray();
            for (stage.devices) |d| try j.write(nl.graph.edges.items(.name)[d]);
            try j.endArray();
        }
        try j.endArray();
        try j.objectField("output_pairs");
        try j.beginArray();
        for (try np.parent_outputs.collect(a, ctx, r)) |pair| {
            try j.beginArray();
            for (pair) |side| try j.write(.{ .net = nl.graph.vertices.items(.name)[side.net], .pmos = nl.graph.edges.items(.name)[side.pmos], .nmos = nl.graph.edges.items(.name)[side.nmos], .gate = nl.graph.edges.items(.name)[side.gate] });
            try j.endArray();
        }
        try j.endArray();
        try j.endObject();
        try sw.interface.writeByte('\n');
    }
    try sw.interface.flush();
}

// ---- private ----
fn write(j: *J, path: []const u8, nl: *const np.netlist.Netlist, r: np.local_parents.Parents) !void {
    const names = nl.graph.edges.items(.name);
    const nets = nl.graph.vertices.items(.name);
    try j.beginObject();
    try j.objectField("id");
    try j.write(std.fs.path.stem(path));
    try j.objectField("disposition");
    try j.write(@tagName(r.disposition));
    try j.objectField("reasons");
    try j.beginArray();
    var reasons = r.reasons.iterator();
    while (reasons.next()) |why| try j.write(@tagName(why));
    try j.endArray();
    if (r.channel.len > 0) {
        try j.objectField("channel_components");
        try groups(j, names, r.channel, r.channel_count);
        try j.objectField("complete_gate_interfaces");
        try j.beginArray();
        for (r.interfaces) |i| try j.write(.{ .device = names[i.device], .gate = nets[i.gate], .kind = @tagName(i.kind), .consumer = i.consumer, .producer = i.producer });
        try j.endArray();
    }
    if (r.groups.len > 0) {
        try j.objectField("proposed_groups");
        try groups(j, names, r.groups, r.group_count);
    }
    if (r.groups.len > 0 and r.disposition != .single_channel_core_keep) {
        try j.objectField("group_dependencies");
        try j.beginObject();
        for (0..r.group_count) |owner| {
            var digits: [16]u8 = undefined;
            try j.objectField(try std.fmt.bufPrint(&digits, "{d}", .{owner}));
            try j.beginArray();
            for (r.dependencies) |e| if (e.source == owner) try j.write(e.target);
            try j.endArray();
        }
        try j.endObject();
    }
    if (r.search) |s| {
        try j.objectField("search");
        try j.write(@tagName(s.state));
        if (s.state == .complete_unique) {
            const m = s.first.?;
            try j.objectField("unique_reflection");
            try j.beginObject();
            try j.objectField("devices");
            try map(j, names, m.devices);
            try j.objectField("nets");
            try map(j, nets, m.nets);
            try j.endObject();
        }
    }
}
fn groups(j: *J, names: []const []const u8, owner: []const u32, count: u32) !void {
    try j.beginArray();
    for (0..count) |i| {
        try j.beginArray();
        for (owner, names) |id, name| if (id == i) try j.write(name);
        try j.endArray();
    }
    try j.endArray();
}
fn map(j: *J, names: []const []const u8, ids: []const u32) !void {
    try j.beginObject();
    for (names, ids) |name, id| if (id != std.math.maxInt(u32)) {
        try j.objectField(name);
        try j.write(names[id]);
    };
    try j.endObject();
}

fn edgeNames(j: *J, nl: *const np.netlist.Netlist, ids: []const np.netlist.EdgeId) !void {
    try j.beginArray();
    for (ids) |e| try j.write(nl.graph.edges.items(.name)[e.index()]);
    try j.endArray();
}

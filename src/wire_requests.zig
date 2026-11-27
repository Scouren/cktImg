//! Admitted geometry intent borrowed while scaffolding defers its execution.
//! Human Rules: absolute route/via and device-at requests still take
//! precedence over an automatic stage's routing preference before compaction.
//! Both CT control queries need the original slices; effective scaffold
//! routes and placements may temporarily be empty.
//!
//! Data: two read-only slices owned by drawValid, alive through its wiring
//! phases. No allocation, flags, mutation or per-candidate query. The view
//! travels once per wiring call, and each cold stage checks its own members.
//!
//! Contents:
//! - `pub const Requests = struct`

const std = @import("std");
const netlines = @import("netlines.zig");
const pinned = @import("pinned.zig");

/// Original admitted paths and device poses; ats spans every device.
/// Routing executes its separate effective tables, never this passive view.
pub const Requests = struct {
    routes: []const netlines.Route,
    ats: []const ?pinned.At,
};

comptime {
    std.debug.assert(@sizeOf(Requests) == 4 * @sizeOf(usize));
}

//! Runtime-input assembly proof for the ordinary trunk entry wrapper.
//! Both exports take the same mutable canvas, net, pins and end request.
//! The generated side uses draw; the direct side calls drawPreferred with
//! null. This proves wrapper overhead only, not that optional interval
//! selection or the new tie policy is free. Never linked into the product.
//!
//! Contents: two private C-ABI exports for the fixed-target codegen gate.

const Canvas = @import("canvas.zig").Canvas;
const trunk = @import("trunk.zig");

// ---- private ----

export fn gen_trunk_null(c: *Canvas, net: u32, ptr: [*]const u32, len: usize, named: bool) u8 {
    const drawn = trunk.draw(c, net, ptr[0..len], if (named) .name else .port) catch return 2;
    return @intFromBool(drawn);
}

export fn hand_trunk_null(c: *Canvas, net: u32, ptr: [*]const u32, len: usize, named: bool) u8 {
    const drawn = trunk.drawPreferred(c, net, ptr[0..len], if (named) .name else .port, null) catch return 2;
    return @intFromBool(drawn);
}

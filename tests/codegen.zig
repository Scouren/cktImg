//! Runtime-input assembly proof for the shared analog-output query.
//! The generated path calls the concrete helper; the hand path performs
//! complete recognition and the output scan directly. Neither export is
//! executed or linked into the product. Ports are runtime pointer/length
//! pairs, so the compiler cannot replace recognition with a constant.
//! Both paths produce the same optional four-bit index before converting
//! it to the exported byte; the hand path calls no shared output helper.
//!
//! Contents: two private C-ABI exports for the fixed-target codegen gate.

const std = @import("std");
const np = @import("NetlistParser");

// ---- private ----

export fn gen_analog_output(name_ptr: [*]const u8, name_len: usize, ports_ptr: [*]const []const u8, ports_len: usize) u8 {
    return if (np.block_symbols.analogOutput(name_ptr[0..name_len], ports_ptr[0..ports_len])) |index| index else 255;
}

export fn hand_analog_output(name_ptr: [*]const u8, name_len: usize, ports_ptr: [*]const []const u8, ports_len: usize) u8 {
    const ports = ports_ptr[0..ports_len];
    const reference = switch (np.block_symbols.identify(name_ptr[0..name_len], ports)) {
        .amplifier, .four_bias_amplifier => false,
        .reference_amplifier => true,
        else => return 255,
    };
    // Complete accepted contracts have two through nine terminals.
    std.debug.assert(ports.len >= 2);
    std.debug.assert(ports.len <= 9);
    for (ports, 0..) |port, i| {
        const is_output = if (reference)
            std.ascii.eqlIgnoreCase(port, "out") or std.ascii.eqlIgnoreCase(port, "vea")
        else
            np.library.portRole(ports, port) == .out;
        if (is_output) return @as(u4, @intCast(i));
    }
    unreachable;
}

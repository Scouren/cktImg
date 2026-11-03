//! The Schemify import over every fixture, natively: each converts without a crash and
//! twice to the same bytes (determinism is a test). Connectivity is the round trip's job:
//! `tests/schemify_roundtrip.sh` netlists the output through Schemify and compares it with
//! the input.

const std = @import("std");
const cktimg = @import("cktimg");

const fixtures = [_][]const u8{
    "power/bandgap_reference.sp",
    "bjt/bjt_current_mirror.sp",
    "bjt/bjt_diff_pair.sp",
    "power/buck_converter.sp",
    "bus/bus_4bit_flash_adc.sp",
    "bus/bus_8bit_dac.sp",
    "bus/bus_current_dac.sp",
    "bus/bus_data_bus_driver.sp",
    "bus/bus_decoder_2to4.sp",
    "bus/bus_mux_4to1.sp",
    "bus/bus_parallel_adder.sp",
    "bus/bus_shift_register.sp",
    "bus/bus_sram_cell_array.sp",
    "bjt/cascode_amplifier.sp",
    "mosfet/cascode_current_mirror.sp",
    "power/charge_pump.sp",
    "mixed_signal/charge_pump_pll.sp",
    "mosfet/cmos_inverter.sp",
    "bjt/common_emitter.sp",
    "mosfet/common_source.sp",
    "mosfet/common_source_active_load.sp",
    "mixed_signal/comparator.sp",
    "hand/default_after_override.sp",
    "opamp/differentiator.sp",
    "bjt/emitter_follower.sp",
    "mosfet/folded_cascode_ota.sp",
    "opamp/instrumentation_amp.sp",
    "opamp/integrator.sp",
    "opamp/inverting_amplifier.sp",
    "power/ldo_regulator.sp",
    "hand/library_only.sp",
    "mosfet/mosfet_current_mirror.sp",
    "mosfet/mosfet_diff_pair.sp",
    "digital/nand_gate.sp",
    "opamp/noninverting_amplifier.sp",
    "digital/nor_gate.sp",
    "hand/params_hierarchy.sp",
    "mixed_signal/phase_detector.sp",
    "mixed_signal/r2r_dac.sp",
    "hand/raw_cards.sp",
    "basic/rc_integrator.sp",
    "basic/rc_lowpass.sp",
    "digital/ring_oscillator.sp",
    "basic/rl_highpass.sp",
    "basic/rlc_bandpass.sp",
    "mixed_signal/sample_and_hold.sp",
    "mosfet/source_follower.sp",
    "digital/sr_latch.sp",
    "opamp/summing_amplifier.sp",
    "testbench/tb_bandgap_temp.sp",
    "testbench/tb_buck_converter_waveform.sp",
    "testbench/tb_charge_pump_waveform.sp",
    "testbench/tb_cmos_inverter_transient.sp",
    "testbench/tb_cmos_inverter_vtc.sp",
    "testbench/tb_common_source_ac.sp",
    "testbench/tb_common_source_dc.sp",
    "testbench/tb_comparator_speed.sp",
    "testbench/tb_current_mirror_compliance.sp",
    "testbench/tb_diff_pair_cmrr.sp",
    "testbench/tb_diff_pair_offset.sp",
    "testbench/tb_diff_pair_transient.sp",
    "testbench/tb_ldo_load_regulation.sp",
    "testbench/tb_ldo_psrr.sp",
    "testbench/tb_rc_lowpass_ac.sp",
    "testbench/tb_rc_lowpass_bode.sp",
    "testbench/tb_rc_lowpass_step.sp",
    "testbench/tb_ring_osc_waveform.sp",
    "testbench/tb_ring_oscillator_freq.sp",
    "testbench/tb_telescopic_ota_full.sp",
    "testbench/tb_two_stage_opamp_cl.sp",
    "testbench/tb_two_stage_opamp_ol.sp",
    "testbench/tb_vco_kvco.sp",
    "testbench/tb_voltage_divider.sp",
    "mosfet/telescopic_ota.sp",
    "digital/transmission_gate.sp",
    "mosfet/two_stage_opamp.sp",
    "mixed_signal/vco.sp",
    "basic/voltage_divider.sp",
    "basic/wheatstone_bridge.sp",
    "mosfet/wilson_mirror.sp",
    "hand/xspice_cards.sp",
};

fn bytesOf(gpa: std.mem.Allocator, a: std.mem.Allocator, name: []const u8, text: []const u8) ![]const u8 {
    const out = try cktimg.convert(gpa, a, name, text);
    var all: std.ArrayList(u8) = .empty;
    for (out.files.items) |f| {
        try std.testing.expect(std.mem.startsWith(u8, f.bytes, "schemify 1 "));
        try all.print(a, "== {s}\n{s}", .{ f.name, f.bytes });
    }
    return all.items;
}

test "every fixture converts, deterministically" {
    inline for (fixtures) |name| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const text = @embedFile("fixtures/" ++ name);
        const source = "n2s/" ++ name;
        const first = try bytesOf(std.testing.allocator, a, source, text);
        const again = try bytesOf(std.testing.allocator, a, source, text);
        std.testing.expectEqualStrings(first, again) catch |e| {
            std.debug.print("{s}: output differs between two runs\n", .{name});
            return e;
        };
    }
}

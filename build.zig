//! Build graph for the engine, front ends, consumer tests and codegen proof.
//! Every generated artifact has an explicit output; checker inputs are
//! declared files. Product targets exclude the test-only assembly probe.
//!
//! Contents:
//! - `pub fn build(b: *std.Build) void`

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const latex_renderer = b.option(bool, "latex_renderer", "Build the TikZ emitter and cktimg-tex") orelse false;
    const zon_config = b.option(bool, "zon_config", "Let the C ABI read lint.zon settings and .zon symbol files (links Zig's ZON parser)") orelse true;
    const options = b.addOptions();
    options.addOption(bool, "latex_renderer", latex_renderer);
    options.addOption(bool, "zon_config", zon_config);
    options.addOption(bool, "c_abi", true);

    const mod = b.addModule("NetlistParser", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        // A host that links libcktimg.a into a PIE or a shared object (gcc's and Rust's
        // default executables on Linux) needs position-independent code.
        .pic = b.option(bool, "pic", "Compile position-independent code (to link libcktimg.a into a PIE or a shared object)"),
    });
    mod.addOptions("build_options", options);

    // libcktimg.a and its header: the C ABI (src/abi.zig). `zig build lib` installs only
    // these, for a host that links the library (and on targets the tools do not build for).
    const static = b.addLibrary(.{ .name = "cktimg", .linkage = .static, .root_module = mod });
    // A freestanding host (a wasm guest) has no C runtime to supply compiler-rt's f128
    // helpers (`__divtf3`, `truncl`, ...), so the archive carries them.
    if (target.result.os.tag == .freestanding) static.bundle_compiler_rt = true;
    b.installArtifact(static);
    b.installFile("include/cktimg.h", "include/cktimg.h");
    const lib_step = b.step("lib", "Build libcktimg.a and install it with include/cktimg.h");
    lib_step.dependOn(&b.addInstallArtifact(static, .{}).step);
    lib_step.dependOn(&b.addInstallFile(b.path("include/cktimg.h"), "include/cktimg.h").step);
    if (b.option(bool, "schemify_plugin", "Build netlist-import.wasm, the Schemify plugin (tools/schemify/), into the repository root") orelse false)
        schemifyPlugin(b);

    // The tools need an OS (files, a clock); a freestanding target (wasm) gets the library only.
    if (target.result.os.tag == .freestanding) return;

    // The standard symbol set, for the tools (the library itself has none).
    const sym_files = b.addWriteFiles();
    _ = sym_files.addCopyFile(b.path("tests/symbols.zon"), "symbols.zon");
    const symbols = b.createModule(.{ .root_source_file = sym_files.add("symbols.zig", "pub const text = @embedFile(\"symbols.zon\");\n") });

    // Unit tests inside the library (netlist, csr, library, config, …).
    const lib_tests = b.addTest(.{ .root_module = mod });

    // The algorithm and API suites, as a consumer sees the module.
    const tool_imports: []const std.Build.Module.Import = &.{.{ .name = "NetlistParser", .module = mod }};
    const cases = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/cases.zig"),
        .target = target,
        .optimize = optimize,
        .imports = tool_imports,
    }) });
    // The Schemify import's transforms, natively against the same engine (its glue,
    // tools/schemify/plugin.zig, is wasm-only), and over every fixture (tests/schemify.zig).
    const convert = b.createModule(.{
        .root_source_file = b.path("tools/schemify/convert.zig"),
        .target = target,
        .optimize = optimize,
        .imports = tool_imports,
    });
    const plugin_tests = b.addTest(.{ .root_module = convert });
    const fixture_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/schemify.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "cktimg", .module = convert }, .{ .name = "NetlistParser", .module = mod } },
    }) });
    // The example decks, for the API suite's connectivity check.
    const ex_files = b.addWriteFiles();
    _ = ex_files.addCopyFile(b.path("examples/blocks.spice"), "blocks.spice");
    _ = ex_files.addCopyFile(b.path("examples/latex/cs.cir"), "cs.cir");
    const parent_sources = b.addWriteFiles();
    const parent_names = [_][]const u8{ "ag-1053.cir", "ag-1079.cir", "ag-1080.cir" };
    for (parent_names) |name| _ = parent_sources.addCopyFile(b.path(b.fmt("external/examples/analoggenie/{s}", .{name})), name);
    const parent_examples = b.createModule(.{ .root_source_file = parent_sources.add("parent_examples.zig", "pub const decks = .{ @embedFile(\"ag-1053.cir\"), @embedFile(\"ag-1079.cir\"), @embedFile(\"ag-1080.cir\") };\n") });
    const examples = b.createModule(.{ .root_source_file = ex_files.add("examples.zig", "pub const all = [_][]const u8{ @embedFile(\"blocks.spice\"), @embedFile(\"cs.cir\") };\n") });
    const api = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/api.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "NetlistParser", .module = mod }, .{ .name = "examples", .module = examples }, .{ .name = "parent_examples", .module = parent_examples } },
    }) });

    // The C ABI as a C program uses it.
    const abi_test = b.addExecutable(.{ .name = "abi_test", .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    }) });
    abi_test.root_module.addCSourceFile(.{ .file = b.path("tests/abi_test.c"), .flags = &.{ "-std=c99", "-Wall", "-Wextra", "-Werror" } });
    abi_test.root_module.addIncludePath(b.path("include"));
    abi_test.root_module.linkLibrary(static);

    const filled_circle_abi = b.addExecutable(.{ .name = "filled_circle_abi", .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    }) });
    filled_circle_abi.root_module.addCSourceFile(.{ .file = b.path("tests/filled_circle_abi.c"), .flags = &.{ "-std=c99", "-Wall", "-Wextra", "-Werror", "-DCKTIMG_TEST_PUBLISHED_FILLED_CIRCLE=1" } });
    filled_circle_abi.root_module.addIncludePath(b.path("include"));
    filled_circle_abi.root_module.linkLibrary(static);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(lib_tests).step);
    test_step.dependOn(&b.addRunArtifact(cases).step);
    test_step.dependOn(&b.addRunArtifact(api).step);
    const abi_run = b.addRunArtifact(abi_test);
    abi_run.addFileArg(b.path("tests/symbols.zon"));
    test_step.dependOn(&abi_run.step);
    test_step.dependOn(&b.addRunArtifact(filled_circle_abi).step);
    test_step.dependOn(&b.addRunArtifact(plugin_tests).step);
    test_step.dependOn(&b.addRunArtifact(fixture_tests).step);

    // Fixed-target, runtime-input proof for a shared placement query.
    // Only the test graph emits this object; product/WASM builds omit it.
    const probe_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .cpu_model = .{ .explicit = &std.Target.x86.cpu.x86_64_v3 },
    });
    const probe_options = b.addOptions();
    probe_options.addOption(bool, "latex_renderer", false);
    probe_options.addOption(bool, "zon_config", false);
    probe_options.addOption(bool, "c_abi", false);
    const probe_engine = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = probe_target, .optimize = .ReleaseFast });
    probe_engine.addOptions("build_options", probe_options);
    const probe = b.addObject(.{ .name = "codegen-probe", .root_module = b.createModule(.{
        .root_source_file = b.path("tests/codegen.zig"),
        .target = probe_target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "NetlistParser", .module = probe_engine }},
    }) });
    const residue = b.addSystemCommand(&.{"python3"});
    residue.addFileArg(b.path("tools/codegen_check.py"));
    residue.addFileInput(b.path("tools/asm_probe.py"));
    residue.addFileArg(probe.getEmittedAsm());
    residue.addArgs(&.{"gen_analog_output=hand_analog_output"});
    const probe_checks = b.addSystemCommand(&.{"python3"});
    probe_checks.addFileArg(b.path("tools/codegen_check.py"));
    probe_checks.addFileInput(b.path("tools/asm_probe.py"));
    probe_checks.addArg("--self-test");
    const codegen = b.step("test-codegen", "Check fixed-target assembly against direct implementations");
    codegen.dependOn(&residue.step);
    codegen.dependOn(&probe_checks.step);
    test_step.dependOn(codegen);

    const fuzz = b.addExecutable(.{ .name = "fuzz", .root_module = b.createModule(.{
        .root_source_file = b.path("tests/fuzz.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .imports = tool_imports,
    }) });
    const fuzz_run = b.addRunArtifact(fuzz);
    fuzz_run.addPassthruArgs();
    b.step("fuzz", "Random netlists through the pipeline; smallest example per rare case").dependOn(&fuzz_run.step);

    // Layout time, today's engine against issue #8's stages, over every cell the
    // Schemify import hands the engine.
    const fast_mod = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = .ReleaseFast });
    fast_mod.addOptions("build_options", options);
    const bench = b.addExecutable(.{ .name = "bench", .root_module = b.createModule(.{
        .root_source_file = b.path("tests/bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{ .{ .name = "cktimg", .module = b.createModule(.{
            .root_source_file = b.path("tools/schemify/convert.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{.{ .name = "NetlistParser", .module = fast_mod }},
        }) }, .{ .name = "NetlistParser", .module = fast_mod } },
    }) });
    b.step("bench", "Layout time per fixture cell, today's engine against issue #8's stages").dependOn(&b.addRunArtifact(bench).step);

    const gallery = b.addExecutable(.{ .name = "gallery", .root_module = b.createModule(.{
        .root_source_file = b.path("tests/gallery.zig"),
        .target = target,
        .optimize = optimize,
        .imports = tool_imports,
    }) });
    b.installArtifact(gallery);
    const gallery_run = b.addRunArtifact(gallery);
    gallery_run.addPassthruArgs();
    b.step("gallery", "Draw the textbook circuits (--svgs dir | --gallery out.html | in.cir out.svg)").dependOn(&gallery_run.step);

    // cktimg-json: the placed schematic as JSON (and SVG) for scripts.
    const svg_mod = b.createModule(.{ .root_source_file = b.path("tests/svg.zig"), .imports = tool_imports });
    const json_mod = b.createModule(.{
        .root_source_file = b.path("tools/json.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "NetlistParser", .module = mod }, .{ .name = "symbols", .module = symbols }, .{ .name = "svg", .module = svg_mod } },
    });
    const census = b.addExecutable(.{ .name = "parent-census", .root_module = b.createModule(.{
        .root_source_file = b.path("tools/parent_census.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "NetlistParser", .module = mod }, .{ .name = "symbols", .module = symbols }, .{ .name = "svg", .module = svg_mod } },
    }) });
    const census_run = b.addRunArtifact(census);
    census_run.addPassthruArgs();
    census_run.has_side_effects = true;
    b.step("parent-census", "Examine selected-cell MOS parents (one JSON record per input deck)").dependOn(&census_run.step);
    const quad_check = b.addSystemCommand(&.{"python3"});
    quad_check.addFileArg(b.path("tests/quad_slots.py"));
    quad_check.addArtifactArg(census);
    for ([_][]const u8{ "ag-80.cir", "ag-82.cir", "ag-517.cir", "ag-1093.cir" }) |name|
        quad_check.addFileArg(b.path(b.pathJoin(&.{ "external/examples/analoggenie", name })));
    test_step.dependOn(&quad_check.step);
    const source_check = b.addSystemCommand(&.{"python3"});
    source_check.addFileArg(b.path("tests/source_regions.py"));
    source_check.addArtifactArg(census);
    for ([_][]const u8{ "ag-220.cir", "ag-396.cir", "ag-459.cir", "ag-517.cir", "ag-558.cir", "ag-718.cir" }) |name|
        source_check.addFileArg(b.path(b.pathJoin(&.{ "external/examples/analoggenie", name })));
    test_step.dependOn(&source_check.step);
    const json_exe = b.addExecutable(.{ .name = "cktimg-json", .root_module = json_mod });
    const signed_frames = b.addSystemCommand(&.{ "python3", "-B" });
    signed_frames.addFileArg(b.path("tests/shared_frames.py"));
    signed_frames.addArtifactArg(json_exe);
    _ = signed_frames.addOutputDirectoryArg("shared-frames");
    for ([_][]const u8{ "tests/shared_frames/mixed.cir", "tests/shared_frames/uniform.cir", "tests/symbols.zon" }) |file|
        signed_frames.addFileInput(b.path(file));
    test_step.dependOn(&signed_frames.step);

    const control_bus = b.addSystemCommand(&.{ "python3", "-B" });
    control_bus.addFileArg(b.path("tests/control_bus_native.py"));
    control_bus.addArtifactArg(json_exe);
    _ = control_bus.addOutputDirectoryArg("control-bus");
    control_bus.addFileInput(b.path("external/examples/analoggenie/ag-1146.cir"));
    test_step.dependOn(&control_bus.step);
    b.installArtifact(json_exe);
    const body_check = b.addSystemCommand(&.{"python3"});
    body_check.addFileArg(b.path("tests/mos_bodies.py"));
    body_check.addArtifactArg(json_exe);
    for ([_][]const u8{ "ag-1181.cir", "ag-1236.cir", "ag-1294.cir", "ag-2287.cir" }) |name|
        body_check.addFileArg(b.path(b.pathJoin(&.{ "external/examples/analoggenie", name })));
    body_check.addFileArg(b.path("tests/symbols.zon"));
    test_step.dependOn(&body_check.step);
    const cap_check = b.addSystemCommand(&.{"python3"});
    cap_check.addFileArg(b.path("tests/polyphase_caps.py"));
    cap_check.addArtifactArg(json_exe);
    for ([_][]const u8{ "ag-493.cir", "ag-493.human.json", "ag-494.cir" }) |name|
        cap_check.addFileArg(b.path(b.pathJoin(&.{ "external/examples/analoggenie", name })));
    test_step.dependOn(&cap_check.step);
    const stage_check = b.addSystemCommand(&.{"python3"});
    stage_check.addFileArg(b.path("tests/parent_stages.py"));
    stage_check.addArtifactArg(json_exe);
    for ([_][]const u8{ "ag-1028.cir", "ag-1046.cir", "ag-1071.cir", "ag-1079.cir", "ag-1080.cir" }) |name|
        stage_check.addFileArg(b.path(b.pathJoin(&.{ "external/examples/analoggenie", name })));
    test_step.dependOn(&stage_check.step);
    const mixer_check = b.addSystemCommand(&.{"python3"});
    mixer_check.addFileArg(b.path("tests/mixer_stage.py"));
    mixer_check.addArtifactArg(json_exe);
    mixer_check.addFileInput(b.path("tests/source_bridge.py"));
    mixer_check.addFileArg(b.path("external/examples/analoggenie/ag-517.cir"));
    test_step.dependOn(&mixer_check.step);
    const folded_check = b.addSystemCommand(&.{"python3"});
    folded_check.addFileArg(b.path("tests/folded_bank.py"));
    folded_check.addArtifactArg(json_exe);
    folded_check.addFileInput(b.path("tests/source_bridge.py"));
    folded_check.addFileArg(b.path("external/examples/analoggenie/ag-1093.cir"));
    test_step.dependOn(&folded_check.step);
    const interleaved = b.addSystemCommand(&.{"python3"});
    interleaved.addFileArg(b.path("tests/interleaved_parents.py"));
    interleaved.addArtifactArg(json_exe);
    interleaved.addFileInput(b.path("tests/source_bridge.py"));
    for ([_][]const u8{ "ag-364.cir", "ag-1016.cir" }) |name|
        interleaved.addFileArg(b.path(b.pathJoin(&.{ "external/examples/analoggenie", name })));
    test_step.dependOn(&interleaved.step);
    const amp_check = b.addSystemCommand(&.{"python3"});
    amp_check.addFileArg(b.path("tests/amplifier_steering.py"));
    amp_check.addArtifactArg(json_exe);
    amp_check.addFileArg(b.path("external/examples/analoggenie/ag-762.cir"));
    test_step.dependOn(&amp_check.step);
    const bridge_check = b.addSystemCommand(&.{"python3"});
    bridge_check.addFileArg(b.path("tests/source_bridge.py"));
    bridge_check.addArtifactArg(json_exe);
    for ([_][]const u8{ "ag-220.cir", "ag-396.cir" }) |name|
        bridge_check.addFileArg(b.path(b.pathJoin(&.{ "external/examples/analoggenie", name })));
    bridge_check.addFileArg(b.path("tests/symbols.zon"));
    bridge_check.addFileArg(b.path("external/examples/amsnet/amsnet-530.cir"));
    bridge_check.addFileArg(b.path("external/examples/amsnet/amsnet-530.human.json"));
    test_step.dependOn(&bridge_check.step);

    const diagonal_check = b.addSystemCommand(&.{"python3"});
    diagonal_check.addFileArg(b.path("tests/diagonal_feedback.py"));
    diagonal_check.addArtifactArg(json_exe);
    for ([_][]const u8{ "ag-90.cir", "ag-404.cir", "ag-647.cir", "ag-493.cir", "ag-1080.cir" }) |name|
        diagonal_check.addFileArg(b.path(b.pathJoin(&.{ "external/examples/analoggenie", name })));
    test_step.dependOn(&diagonal_check.step);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = json_mod })).step);

    if (latex_renderer) {
        const tex = b.addExecutable(.{ .name = "cktimg-tex", .root_module = b.createModule(.{
            .root_source_file = b.path("tools/tex.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{ .{ .name = "NetlistParser", .module = mod }, .{ .name = "symbols", .module = symbols } },
        }) });
        b.installArtifact(tex);
        const figures = b.addSystemCommand(&.{ "python3", "-B" });
        figures.addFileArg(b.path("tests/tex_selection.py"));
        figures.addArtifactArg(json_exe);
        figures.addArtifactArg(tex);
        _ = figures.addOutputDirectoryArg("tikz-selection");
        for ([_][]const u8{ "tests/parent_stages.py", "tests/symbols.zon", "examples/latex/cs.cir", "external/examples/analoggenie/ag-1080.cir", "external/examples/analoggenie/ag-2212.cir", "external/examples/analoggenie/ag-808.cir", "external/examples/analoggenie/ag-220.cir" }) |file|
            figures.addFileInput(b.path(file));
        test_step.dependOn(&figures.step);
        b.installFile("latex/cktimg.sty", "share/latex/cktimg.sty");
    }
}

/// netlist-import.wasm next to schemify.project (committed; `plugin netlist-import path netlist-import.wasm`):
/// wasm32-freestanding, ReleaseSmall, the engine without its C ABI or ZON parser.
// ---- private ----

fn schemifyPlugin(b: *std.Build) void {
    const wasm = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const options = b.addOptions();
    options.addOption(bool, "latex_renderer", false);
    options.addOption(bool, "zon_config", false);
    options.addOption(bool, "c_abi", false);
    const engine = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = wasm, .optimize = .ReleaseSmall });
    engine.addOptions("build_options", options);
    const convert = b.createModule(.{
        .root_source_file = b.path("tools/schemify/convert.zig"),
        .imports = &.{.{ .name = "NetlistParser", .module = engine }},
    });
    const exe = b.addExecutable(.{
        .name = "netlist-import",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/schemify/plugin.zig"),
            .target = wasm,
            .optimize = .ReleaseSmall,
            .strip = true,
            .imports = &.{
                .{ .name = "NetlistParser", .module = engine },
                .{ .name = "cktimg", .module = convert },
                // Schemify's plugin ABI v1, vendored (tools/schemify/abi.zig names its revision).
                .{ .name = "schemify", .module = b.createModule(.{ .root_source_file = b.path("tools/schemify/abi.zig") }) },
            },
        }),
    });
    exe.lto = .full; // optimize the complete guest together at the final size-limited link
    exe.entry = .disabled; // a plugin has no main
    exe.rdynamic = true; // keep the schemify_* exports
    // Keep only the guest's existing WebAssembly features. The ordinary library and
    // native tools have no optimizer dependency. Nix supplies the pinned Binaryen.
    const optimize_guest = b.addSystemCommand(&.{ "wasm-opt", "-Oz", "--enable-bulk-memory", "--enable-sign-ext", "--enable-mutable-globals", "--enable-nontrapping-float-to-int" });
    optimize_guest.addFileInput(b.path("flake.lock"));
    optimize_guest.addFileArg(exe.getEmittedBin());
    optimize_guest.addArg("-o");
    const guest = optimize_guest.addOutputFileArg("netlist-import.wasm");
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(guest, .prefix, "../netlist-import.wasm").step);
}

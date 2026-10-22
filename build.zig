const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const util_module = b.createModule(.{
        .root_source_file = b.path("vendor/yuku/src/util/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const codegen_options = b.addOptions();
    codegen_options.addOption(bool, "source_maps", true);
    const dialect_module = b.addOptions().createModule();

    const parser_module = b.createModule(.{
        .root_source_file = b.path("vendor/yuku/src/parser/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    parser_module.addImport("util", util_module);
    parser_module.addImport("codegen_options", codegen_options.createModule());
    parser_module.addImport("dialect", dialect_module);

    const lint_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lint_module.addImport("parser", parser_module);

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_module.addImport("utoo_lint", lint_module);

    const exe = b.addExecutable(.{
        .name = "utoo-lint",
        .root_module = exe_module,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run utoo-lint");
    run_step.dependOn(&run_cmd.step);

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .cpu_features_add = std.Target.wasm.featureSet(&.{
            .bulk_memory,
            .nontrapping_fptoint,
            .sign_ext,
            .simd128,
        }),
    });

    const wasm_util_module = b.createModule(.{
        .root_source_file = b.path("vendor/yuku/src/util/root.zig"),
        .target = wasm_target,
        .optimize = .small,
    });

    const wasm_parser_module = b.createModule(.{
        .root_source_file = b.path("vendor/yuku/src/parser/root.zig"),
        .target = wasm_target,
        .optimize = .small,
    });
    wasm_parser_module.addImport("util", wasm_util_module);
    wasm_parser_module.addImport("codegen_options", codegen_options.createModule());
    wasm_parser_module.addImport("dialect", dialect_module);

    const wasm_lint_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = wasm_target,
        .optimize = .small,
    });
    wasm_lint_module.addImport("parser", wasm_parser_module);

    const wasm_module = b.createModule(.{
        .root_source_file = b.path("src/wasm.zig"),
        .target = wasm_target,
        .optimize = .small,
        .strip = true,
    });
    wasm_module.addImport("utoo_lint", wasm_lint_module);

    const wasm = b.addExecutable(.{
        .name = "utoo-lint",
        .root_module = wasm_module,
    });
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    // Options is currently a large value type and passes through several stack
    // frames. Keep enough linear-memory stack for browser calls until it is
    // refactored to pass by pointer.
    wasm.stack_size = 8 * 1024 * 1024;

    const wasm_step = b.step("wasm", "Build the WebAssembly module");
    wasm_step.dependOn(&b.addInstallArtifact(wasm, .{}).step);

    const run_wasm_tests = b.addSystemCommand(&.{"node"});
    run_wasm_tests.addFileArg(b.path("tests/wasm.mjs"));
    run_wasm_tests.addFileArg(wasm.getEmittedBin());
    const wasm_test_step = b.step("test-wasm", "Build and test the WebAssembly module");
    wasm_test_step.dependOn(&run_wasm_tests.step);

    const test_module = b.createModule(.{
        .root_source_file = b.path("tests/all.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("utoo_lint", lint_module);
    const flat_config_test_module = b.createModule(.{
        .root_source_file = b.path("src/flat_config.zig"),
        .target = target,
        .optimize = optimize,
    });
    flat_config_test_module.addImport("utoo_lint", lint_module);
    test_module.addImport("flat_config", flat_config_test_module);

    const unit_tests = b.addTest(.{
        .root_module = test_module,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const snapshot_module = b.createModule(.{
        .root_source_file = b.path("tests/snapshots/runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    snapshot_module.addImport("utoo_lint", lint_module);

    const snapshot_runner = b.addExecutable(.{
        .name = "rule-snapshots",
        .root_module = snapshot_module,
    });

    const run_snapshot_tests = b.addRunArtifact(snapshot_runner);
    run_snapshot_tests.setCwd(b.path("."));
    const snapshot_test_step = b.step("test-snapshots", "Verify rule snapshots");
    snapshot_test_step.dependOn(&run_snapshot_tests.step);

    const update_snapshot_tests = b.addRunArtifact(snapshot_runner);
    update_snapshot_tests.setCwd(b.path("."));
    update_snapshot_tests.addArg("--update");
    const snapshot_update_step = b.step("update-snapshots", "Update rule snapshots");
    snapshot_update_step.dependOn(&update_snapshot_tests.step);

    const test_step = b.step("test", "Run unit tests and rule snapshots");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_snapshot_tests.step);
}

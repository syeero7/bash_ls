const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tree_sitter = b.dependency("tree_sitter", .{
        .target = target,
        .optimize = optimize,
    });

    const tree_sitter_bash = b.dependency("tree_sitter_bash", .{
        .target = target,
        .optimize = optimize,
    });

    const main_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_module.addImport("tree_sitter", tree_sitter.module("tree_sitter"));
    main_module.addCSourceFiles(.{
        .root = tree_sitter_bash.path("src"),
        .files = &.{ "parser.c", "scanner.c" },
    });

    const exe = b.addExecutable(.{
        .name = "bash_ls",
        .root_module = main_module,
    });
    b.installArtifact(exe);

    const run_exe_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_exe_cmd.step);
    run_exe_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_exe_cmd.addArgs(args);

    const tests = b.addTest(.{ .root_module = main_module });
    const run_tests_cmd = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests_cmd.step);
}

const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "bash_ls",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.standardTargetOptions(.{}),
            .optimize = b.standardOptimizeOption(.{}),
        }),
    });

    b.installArtifact(exe);

    const run_exe_cmd = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_exe_cmd.step);
    run_exe_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_exe_cmd.addArgs(args);

    const tests = b.addTest(.{ .root_module = exe.root_module });
    const run_tests_cmd = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests_cmd.step);
}

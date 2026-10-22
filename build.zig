const std = @import("std");
const Build = std.Build;
const ResolvedTarget = Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;

const targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    // .{ .cpu_arch = .x86_64, .os_tag = .windows },
};

pub fn build(b: *Build) !void {
    const should_build_multi_targets = b.option(bool, "multi-targets", "Build for multiple targets");
    const optimize = b.standardOptimizeOption(.{});

    if (should_build_multi_targets) |_| {
        for (targets) |query| {
            const target = b.resolveTargetQuery(query);
            const main_module = getModule(b, target, optimize);
            const suffix = try query.zigTriple(b.allocator);
            const exe = b.addExecutable(.{
                .name = b.fmt("bash_ls-{s}", .{suffix}),
                .root_module = main_module,
            });

            b.installArtifact(exe);
        }

        return;
    }

    const target = b.standardTargetOptions(.{});
    const main_module = getModule(b, target, optimize);
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

fn getModule(b: *Build, target: ResolvedTarget, optimize: OptimizeMode) *Build.Module {
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

    return main_module;
}

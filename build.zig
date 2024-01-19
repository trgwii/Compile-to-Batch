const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "BetterBatch",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.defineCMacro("BUILDING_WITH_ZIG", null);
    exe.addCSourceFiles(.{
        .files = &.{"src/main.c"},
        .flags = &[_][]const u8{
            "-Weverything",
            "-Werror",
            "-Wno-padded",
            "-Wno-declaration-after-statement",
            "-Wno-unsafe-buffer-usage",
            "-Wno-used-but-marked-unused",
        },
    });
    exe.linkLibC();
    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

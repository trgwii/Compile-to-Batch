const std = @import("std");

pub fn build(b: *std.Build) void {
    const emitC = b.option(bool, "emit_c", "Emit C instead of binary");
    const target = b.standardTargetOptions(
        if (emitC orelse false) .{ .default_target = .{ .ofmt = .c } } else .{},
    );
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "bc",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    // exe.defineCMacro("BUILDING_WITH_ZIG", null);
    // exe.addCSourceFiles(.{
    //     .files = &.{"src/main.c"},
    //     .flags = &[_][]const u8{
    //         "-Weverything",
    //         "-Werror",
    //         "-Wno-padded",
    //         "-Wno-declaration-after-statement",
    //         "-Wno-unsafe-buffer-usage",
    //         "-Wno-used-but-marked-unused",
    //         "-Wno-disabled-macro-expansion",
    //     },
    // });
    exe.linkLibC();
    b.installArtifact(exe);
    if (!(emitC orelse false)) {
        const lib = b.addStaticLibrary(.{
            .name = "bc",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });
        lib.linkLibC();
        b.installArtifact(lib);
    }
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addArgs(&.{ "main.bb", "main.cmd" });
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

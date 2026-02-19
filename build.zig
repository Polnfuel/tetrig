const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = .Debug;

    const termenv = b.addModule("termenv", .{
        .root_source_file = b.path("src/termenv.zig"),
        .target = target,
    });

    const game = b.addModule("game", .{ .root_source_file = b.path("src/game.zig"), .target = target, .imports = &.{
        .{ .name = "termenv", .module = termenv },
    } });

    const exe = b.addExecutable(.{
        .name = "tetr",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "termenv", .module = termenv },
                .{ .name = "game", .module = game },
            },
        }),
        .use_llvm = true,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}

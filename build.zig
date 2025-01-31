const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // library
    const lib = b.addStaticLibrary(.{
        .name = "tokenizig",
        .root_source_file = b.path("src/tokenizer.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();  // Required to link the `regex.h` C library
    b.installArtifact(lib);

    // library tests
    const tests = b.addTest(.{
        .root_source_file = b.path("src/tokenizer.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.linkLibC();

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    // binary
    const exe = b.addExecutable(.{
        .name = "tokenizig-cli",
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(lib);
    exe.linkLibC();  // Inherit C linking from library
    b.installArtifact(exe);
}

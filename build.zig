const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "regex",
        .root_source_file = b.path("src/regex.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Required to link the `regex.h` C library
    lib.linkLibC();
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/regex.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.linkLibC();

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
}

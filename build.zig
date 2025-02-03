const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "tokeni",
        .root_source_file = b.path("src/tokenizer.zig"),
        .target = target,
        .optimize = optimize,
    });
    // required to link the `regex.h` c library
    lib.linkLibC();
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/tokenizer.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests.linkLibC();

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);
}

const std = @import("std");
const Tokenizer = @import("./tokenizer.zig").Tokenizer;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <input-file>\n", .{args[0]});
        return error.MissingFilePath;
    }

    var special_tokens = std.ArrayList([]const u8).init(allocator);
    defer special_tokens.deinit();
    try special_tokens.append("<|endoftext|>");

    var tokenizer = try Tokenizer.init(
        "vocab.json",
        "merges.txt",
        "('s|'t|'re|'ve|'m|'ll|'d| ?[[:alpha:]]+| ?[[:digit:]]+| ?[^[:alnum:][:space:]]+| +[[:space:]]*| +)",
        special_tokens,
        allocator
    );
    defer tokenizer.deinit();

    const input_file = try std.fs.cwd().openFile(args[1], .{});
    defer input_file.close();

    const input_text = try input_file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(input_text);

    const suffix = "<|endoftext|>";
    var buffer = try allocator.alloc(u8, input_text.len + suffix.len);
    defer allocator.free(buffer);

    std.mem.copyForwards(u8, buffer[0..input_text.len], input_text);
    std.mem.copyForwards(u8, buffer[input_text.len..], suffix);

    _ = try tokenizer.encode(buffer);

    const iterations = 10;
    var timer = try std.time.Timer.start();
    for (0..iterations) |_| {
        const input_ids = try tokenizer.encode(buffer);
        defer allocator.free(input_ids);

        try std.testing.expectEqual(@as(u32, 50256), input_ids[input_ids.len - 1]);
    }

    const elapsed_ns = timer.read();
    const ns_per_op_ms = (@as(f64, @floatFromInt(elapsed_ns)) / iterations) / 1e6;
    const ns_per_op_s = (@as(f64, @floatFromInt(elapsed_ns)) / iterations) / 1e9;

    std.debug.print(
        \\Benchmark results:
        \\Iterations: {d}
        \\Total time: {d:.2}ms
        \\Time per encode: {d:.2}ms ({d:.4}s)
        \\Throughput: {d:.2}MB/s
        \\
    , .{
        iterations,
        @as(f64, @floatFromInt(elapsed_ns)) / 1e6,
        ns_per_op_ms,
        ns_per_op_s,
        @as(f64, @floatFromInt(input_text.len)) * @as(f64, @floatFromInt(iterations)) / 
        (@as(f64, @floatFromInt(elapsed_ns)) / 1e9) / (1024 * 1024),
    });
}

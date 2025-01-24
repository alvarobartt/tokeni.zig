const std = @import("std");

pub fn bytesToUnicode(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var code_point: [256]u21 = undefined;
    var present = [_]bool{false} ** 256;

    for (33..127) |b_usize| {
        const b = @as(u8, @intCast(b_usize));
        present[b] = true;
        code_point[b] = b;
    }
    for (161..173) |b_usize| {
        const b = @as(u8, @intCast(b_usize));
        present[b] = true;
        code_point[b] = b;
    }
    for (174..256) |b_usize| {
        const b = @as(u8, @intCast(b_usize));
        present[b] = true;
        code_point[b] = b;
    }

    var n: u16 = 0;
    for (0..256) |b_usize| {
        const b = @as(u8, @intCast(b_usize));
        if (!present[b]) {
            code_point[b] = 256 + n;
            n += 1;
        }
    }

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    for (input) |byte| {
        const cp = code_point[byte];
        var utf8_bytes: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(cp, &utf8_bytes);
        try buffer.appendSlice(utf8_bytes[0..len]);
    }

    return buffer.toOwnedSlice();
}

test "bytesToUnicode" {
    const output = try bytesToUnicode(std.testing.allocator, "hello world");
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("helloĠworld", output);
}

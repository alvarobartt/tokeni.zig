const std = @import("std");

pub fn splitSpecialTokens(allocator: std.mem.Allocator, text: []const u8, special_tokens: []const []const u8) ![][]const u8 {
    var result = std.ArrayList([]const u8).init(allocator);
    defer result.deinit();

    // mutable view of immutable data i.e. O(1)
    // meaning that the view is manipulated, not the data
    var current = text;
    while (current.len > 0) {
        var earliest_special_token: ?[]const u8 = null;
        var earliest_index: usize = current.len;

        for (special_tokens) |special_token| {
            if (std.mem.indexOf(u8, current, special_token)) |index| {
                if (index < earliest_index) {
                    earliest_special_token = special_token;
                    earliest_index = index;
                }
            }
        }

        if (earliest_special_token == null) {
            try result.append(current);
            break;
        }

        if (earliest_index > 0) {
            try result.append(current[0..earliest_index]);
        }

        try result.append(earliest_special_token.?);
        current = current[earliest_index + earliest_special_token.?.len..];
    }

    return result.toOwnedSlice();
}

test "splitSpecialTokens" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // use spaces as special tokens as per e.g. https://huggingface.co/vikhyatk/moondream2/blob/main/tokenizer_config.json
    const text = "   A  bbbA   ";
    const special_tokens = &[_][]const u8{ "   ", "  ", " ", "A" };

    const result = try splitSpecialTokens(allocator, text, special_tokens);
    defer allocator.free(result);

    const expected = &[_][]const u8{ "   ", "A", "  ", "bbb", "A", "   " };

    try testing.expectEqual(expected.len, result.len);

    for (expected, 0..) |exp, i| {
        try testing.expectEqualStrings(exp, result[i]);
    }
}

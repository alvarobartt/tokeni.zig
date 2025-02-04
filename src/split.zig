const std = @import("std");

pub fn splitSpecialTokens(allocator: std.mem.Allocator, text: []const u8, special_tokens: []const []const u8) ![][]const u8 {
    var result = std.ArrayList([]const u8).init(allocator);
    errdefer result.deinit();

    // mutable view of immutable data i.e. O(1)
    // meaning that the view is manipulated, not the data
    var current = text;
    while (current.len > 0) {
        var earliest_special_token: ?[]const u8 = null;
        var earliest_index: usize = current.len;

        // loops in order over the provided special tokens and keeps the first
        // special token that's encountered, as it's ordered, assuming that the
        // overlapping sequences are defined in decreasing order of text length,
        // then the earliest in the string will also be the longest if possible,
        // so the next overlapping ones won't match the `index < earliest_index`
        // condition
        for (special_tokens) |special_token| {
            // index here is the starting index of the special token so that the
            // part we need to split is `index + special_token.len`
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

        // if there is text that's not part of the special token i.e. index is
        // anything else than 0, then append the raw text to the result
        if (earliest_index > 0) {
            try result.append(current[0..earliest_index]);
        }

        // then append the special token to the result, and update the current
        // value with the remainder of the text
        try result.append(earliest_special_token.?);
        current = current[earliest_index + earliest_special_token.?.len..];
    }

    return result.toOwnedSlice();
}

test "splitSpecialTokens" {
    const allocator = std.testing.allocator;

    // use spaces as special tokens to ensure that those have priority i.e. the
    // first one is replaced even if there are nested special tokens as per e.g.
    // https://huggingface.co/vikhyatk/moondream2/blob/main/tokenizer_config.json
    // that contains different space sequences being the first one the longest
    const text = "   A  bbbA   ";
    const special_tokens = &[_][]const u8{ "   ", "  ", " ", "A" };

    const result = try splitSpecialTokens(allocator, text, special_tokens);
    defer allocator.free(result);

    const expected = &[_][]const u8{ "   ", "A", "  ", "bbb", "A", "   " };
    try std.testing.expectEqual(expected.len, result.len);
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqualStrings(exp, result[i]);
    }
}

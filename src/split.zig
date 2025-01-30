const std = @import("std");

pub fn splitWithDelimiters(
    allocator: std.mem.Allocator, 
    text: []const u8, 
    delimiters: []const []const u8
) ![][]const u8 {
    const sorted_delimiters = try allocator.dupe([]const u8, delimiters);
    defer allocator.free(sorted_delimiters);

    std.mem.sort([]const u8, sorted_delimiters, {}, struct {
        pub fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return a.len > b.len;
        }
    }.lessThan);

    var result = std.ArrayList([]const u8).init(allocator);
    defer result.deinit();

    var current = text;

    while (current.len > 0) {
        var earliest_delimiter: ?[]const u8 = null;
        var earliest_index: usize = current.len;

        for (sorted_delimiters) |delimiter| {
            if (std.mem.indexOf(u8, current, delimiter)) |index| {
                if (index < earliest_index) {
                    earliest_delimiter = delimiter;
                    earliest_index = index;
                }
            }
        }

        if (earliest_delimiter == null) {
            try result.append(current);
            break;
        }

        if (earliest_index > 0) {
            try result.append(current[0..earliest_index]);
        }

        try result.append(earliest_delimiter.?);
        current = current[earliest_index + earliest_delimiter.?.len..];
    }

    return result.toOwnedSlice();
}

test "split with delimiters" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const text = "aaCaaABBBcccAAAC";
    const delimiters = &[_][]const u8{ "A", "BB", "C", "AAA" };

    const result = try splitWithDelimiters(allocator, text, delimiters);
    defer allocator.free(result);

    const expected = &[_][]const u8{ "aa", "C", "aa", "A", "BB", "Bccc", "AAA", "C" };

    try testing.expectEqual(expected.len, result.len);

    for (expected, 0..) |exp, i| {
        try testing.expectEqualStrings(exp, result[i]);
    }
}

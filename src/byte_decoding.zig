const std = @import("std");
const BYTE_TO_TOKEN_MAPPING = @import("byte_encoding.zig").BYTE_TO_TOKEN_MAPPING;

const TokenToByteMapping = struct {
    // holds a reversed mapping as a counterpart of the ByteToTokenMapping, and
    // holds 324 values, as those are the 256 default UTF-8 values that can be represented
    // with 1 byte + the extra 68 values included and remapped as some where initially
    // discarded as non-printable or being control characters e.g. the space
    token_to_byte: [324]u8,
};

fn initializeTokenToByteMapping() TokenToByteMapping {
    var token_to_byte: [324]u8 = undefined;

    for (0..256) |byte_value| {
        const byte = @as(u8, @intCast(byte_value));
        const token_id = BYTE_TO_TOKEN_MAPPING.byte_to_token_map[byte];
        token_to_byte[token_id] = byte;
    }

    return TokenToByteMapping{ .token_to_byte = token_to_byte };
}

const TOKEN_TO_BYTE_MAPPING = initializeTokenToByteMapping();

pub fn tokensToBytes(allocator: std.mem.Allocator, encoded: []const u8) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    // the view is required to iterate over UTF-8 code points instead of bytes, because
    // as mentioned, UTF-8 can be represented with 1-4 bytes
    var view = try std.unicode.Utf8View.init(encoded);
    var it = view.iterator();
    while (it.nextCodepoint()) |codepoint| {
        // maps each token to its original byte value i.e. not the remapped value
        // so in this case e.g. Ġ represented as the token 32, that when converted
        // to the original byte value in the default UTF-8 encoding is the space
        const byte = TOKEN_TO_BYTE_MAPPING.token_to_byte[@as(usize, codepoint)];
        try output.append(byte);
    }

    return output.toOwnedSlice();
}

test "tokensToBytes" {
    const allocator = std.testing.allocator;

    const input = try tokensToBytes(allocator, "helloĠworld");
    defer allocator.free(input);
    try std.testing.expectEqualStrings("hello world", input);
}

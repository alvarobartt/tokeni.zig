const std = @import("std");

const ByteToTokenMapping = struct {
    byte_to_token_map: [256]u21,
};

fn initializeByteToTokenMapping() ByteToTokenMapping {
    var byte_to_token_map: [256]u21 = undefined;
    var is_byte_mapped = [_]bool{false} ** 256;

    for (33..127) |byte_value| {
        const byte = @as(u8, @intCast(byte_value));
        is_byte_mapped[byte] = true;
        byte_to_token_map[byte] = byte;
    }
    for (161..173) |byte_value| {
        const byte = @as(u8, @intCast(byte_value));
        is_byte_mapped[byte] = true;
        byte_to_token_map[byte] = byte;
    }
    for (174..256) |byte_value| {
        const byte = @as(u8, @intCast(byte_value));
        is_byte_mapped[byte] = true;
        byte_to_token_map[byte] = byte;
    }

    var next_token_id: u16 = 0;
    for (0..256) |byte_value| {
        const byte = @as(u8, @intCast(byte_value));
        if (!is_byte_mapped[byte]) {
            byte_to_token_map[byte] = 256 + next_token_id;
            next_token_id += 1;
        }
    }

    return ByteToTokenMapping{ .byte_to_token_map = byte_to_token_map };
}

const BYTE_TO_TOKEN_MAPPING = initializeByteToTokenMapping();

pub fn encodeBytesToTokens(allocator: std.mem.Allocator, utf8_input: []const u8) ![]const u8 {
    var output_buffer = std.ArrayList(u8).init(allocator);
    errdefer output_buffer.deinit();

    for (utf8_input) |utf8_byte| {
        const token_id = BYTE_TO_TOKEN_MAPPING.byte_to_token_map[utf8_byte];
        var encoded_utf8: [4]u8 = undefined;
        const encoded_length = try std.unicode.utf8Encode(token_id, &encoded_utf8);
        try output_buffer.appendSlice(encoded_utf8[0..encoded_length]);
    }

    return output_buffer.toOwnedSlice();
}

const TokenToByteMapping = struct {
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

const TOKEN_TO_BYTE = initializeTokenToByteMapping();

pub fn decodeTokensToBytes(allocator: std.mem.Allocator, encoded: []const u8) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    var utf8_view = try std.unicode.Utf8View.init(encoded);
    var iter = utf8_view.iterator();

    while (iter.nextCodepoint()) |codepoint| {
        const byte = TOKEN_TO_BYTE.token_to_byte[@as(usize, codepoint)];
        try output.append(byte);
    }

    return output.toOwnedSlice();
}

test "encodeBytesToTokens" {
    const allocator = std.testing.allocator;

    const output = try encodeBytesToTokens(allocator, "hello world");
    defer allocator.free(output);
    try std.testing.expectEqualStrings("helloĠworld", output);
}

test "decodeTokensToBytes" {
    const allocator = std.testing.allocator;

    const input = try decodeTokensToBytes(allocator, "helloĠworld");
    defer allocator.free(input);
    try std.testing.expectEqualStrings("hello world", input);
}

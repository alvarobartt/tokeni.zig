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
    defer output_buffer.deinit();

    for (utf8_input) |utf8_byte| {
        const token_id = BYTE_TO_TOKEN_MAPPING.byte_to_token_map[utf8_byte];
        var encoded_utf8: [4]u8 = undefined;
        const encoded_length = try std.unicode.utf8Encode(token_id, &encoded_utf8);
        try output_buffer.appendSlice(encoded_utf8[0..encoded_length]);
    }

    return output_buffer.toOwnedSlice();
}

test "encodeBytesToTokens" {
    const output = try encodeBytesToTokens(std.testing.allocator, "hello world");
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualStrings("helloĠworld", output);
}


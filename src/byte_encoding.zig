const std = @import("std");

const ByteToTokenMapping = struct {
    // utf-8 is a variable width encoding (1..4 bytes),
    // and 1 byte can represent 256 possible values (0..256)
    // u21 to cover the entire unicode space of possible values, with
    // no need of going with e.g. u32, and saving 11 bits
    byte_to_token_map: [256]u21,
};

// removes the non-printable characters amongst the first 256 possible
// values that can be represented in binary within an 8-bit space i.e.
// 11111111 is FF in hex and 255 in decimal
fn initializeByteToTokenMapping() ByteToTokenMapping {
    var byte_to_token_map: [256]u21 = undefined;
    var is_byte_mapped = [_]bool{false} ** 256;

    // 1..33 are control characters, the character with the byte value 32 is the space
    // which is not-printable and will later be replaced by the Ġ character
    // but the values in the 33..127 are printable ascii characters so those are
    // included in the map with their byte value
    for (33..127) |byte_value| {
        const byte = @as(u8, @intCast(byte_value));
        is_byte_mapped[byte] = true;
        byte_to_token_map[byte] = byte;
    }
    // 161..173 and 174..256 maps some non-ascii characters to their byte values,
    // whilst discarding both non-printable and control characters (in extended
    // ascii sets)
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

    // finally, the unmapped bytes get a token assigned starting from the byte
    // value 256 e.g. as mentioned above, the byte value 32 originally corresponding
    // to the space, is now remmapped to the byte value 288 (being 32 + 256) which
    // is represented with 2 bytes but now mapped to the byte value 32
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

// it's initiallized on compile time (no need to add comptime)
pub const BYTE_TO_TOKEN_MAPPING = initializeByteToTokenMapping();

pub fn bytesToTokens(allocator: std.mem.Allocator, utf8_input: []const u8) ![]const u8 {
    var output_buffer = std.ArrayList(u8).init(allocator);
    errdefer output_buffer.deinit();

    for (utf8_input) |utf8_byte| {
        // retrieves the token id corresponding to the current byte e.g. for the
        // space its byte value is 32, so the token corresponding to the byte value
        // 32 is Ġ
        const token_id = BYTE_TO_TOKEN_MAPPING.byte_to_token_map[utf8_byte];
        // because utf-8 characters can be represented with up to 4-bytes
        var encoded_utf8: [4]u8 = undefined;
        // then we encode that value using the UTF-8 encoding, so that e.g. the Ġ
        // is encoded as a 2-byte length value of {196, 160}
        const encoded_length = try std.unicode.utf8Encode(token_id, &encoded_utf8);
        try output_buffer.appendSlice(encoded_utf8[0..encoded_length]);
    }

    return output_buffer.toOwnedSlice();
}

test "bytesToTokens" {
    const allocator = std.testing.allocator;

    const output = try bytesToTokens(allocator, "hello world");
    defer allocator.free(output);
    try std.testing.expectEqualStrings("helloĠworld", output);
}

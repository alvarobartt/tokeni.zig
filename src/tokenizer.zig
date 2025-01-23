const std = @import("std");

pub const Tokenizer = struct {
    vocab: std.StringHashMap(i32),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Tokenizer {
        // https://ziglang.org/documentation/master/std/#std.fs
        const file_content = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
        defer allocator.free(file_content);

        // https://ziglang.org/documentation/master/std/#std.json
        var json_tree = try std.json.parseFromSlice(std.json.Value, allocator, file_content, .{});
        defer json_tree.deinit();

        var hash_map = std.StringHashMap(i32).init(allocator);
        // TODO: maybe this can be pulled from https://huggingface.co/openai-community/gpt2/blob/main/config.json#L30
        try hash_map.ensureTotalCapacity(50257);
        errdefer hash_map.deinit();

        const root = json_tree.value;
        if (root == .object) {
            var it = root.object.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                const value = entry.value_ptr.*;
                if (value == .integer) {
                    try hash_map.put(key, @as(i32, @intCast(value.integer)));
                }
            }
        }

        return .{
            .vocab = hash_map,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Tokenizer) void {
        self.vocab.deinit();
    }
};

test "Tokenizer" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // https://huggingface.co/openai-community/gpt2/blob/main/vocab.json
    var tokenizer = try Tokenizer.init(allocator, "vocab.json");
    defer tokenizer.deinit();
}

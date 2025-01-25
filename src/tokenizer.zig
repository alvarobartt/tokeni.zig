const std = @import("std");
const Regex = @import("regex.zig").Regex;
const bytesToUnicode = @import("bytes.zig").bytesToUnicode;

pub const Tokenizer = struct {
    vocab: std.StringHashMap(u32),
    vocab_r: std.AutoHashMap(u32, []const u8),
    // merges: std.StringHashMap([]const u8),
    regex: Regex,
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    // pub fn init(allocator: std.mem.Allocator, vocab_path: []const u8, merges_path: []const u8) !Tokenizer {
    pub fn init(allocator: std.mem.Allocator, vocab_path: []const u8) !Tokenizer {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const aallocator = arena.allocator();

        var vocab = std.StringHashMap(u32).init(aallocator);
        // TODO: maybe this can be pulled from https://huggingface.co/openai-community/gpt2/blob/main/config.json#L30
        try vocab.ensureTotalCapacity(50257);
        errdefer vocab.deinit();

        var vocab_r = std.AutoHashMap(u32, []const u8).init(aallocator);
        try vocab_r.ensureTotalCapacity(50257);
        errdefer vocab_r.deinit();

        {
            // https://ziglang.org/documentation/master/std/#std.fs
            const vocab_content = try std.fs.cwd().readFileAlloc(aallocator, vocab_path, 1024 * 1024);
            defer aallocator.free(vocab_content);

            // https://ziglang.org/documentation/master/std/#std.json
            var json_tree = try std.json.parseFromSlice(std.json.Value, aallocator, vocab_content, .{});
            defer json_tree.deinit();

            const root = json_tree.value;
            if (root == .object) {
                var it = root.object.iterator();
                while (it.next()) |entry| {
                    // as the key is a `[]const u8` i.e. not a primitive type, we need
                    // to copy it explicitly as otherwise we're just storing the pointer
                    // which can easily go out of scope and leave the `HashMap` invalid
                    const key = try aallocator.dupe(u8, entry.key_ptr.*);
                    // on the other hand for primitive types we don't need to explicitly
                    // copy or dupe those, as those have a fixed size and are easy to copy
                    // and move
                    const value = @as(u32, @intCast(entry.value_ptr.*.integer));
                    try vocab.put(key, value);
                    try vocab_r.put(value, key);
                }
            }
        }

        // var merges = std.StringHashMap([]const u8).init(aallocator);
        // try merges.ensureTotalCapacity(50000);
        // errdefer merges.deinit();
        //
        // {
        //     const merges_content = try std.fs.cwd().readFileAlloc(aallocator, merges_path, 1024 * 1024);
        //     defer aallocator.free(merges_content);
        //
        //     var lines = std.mem.tokenize(u8, merges_content, "\n");
        //     // skip the first line as it contains the `tokenizers` version
        //     // e.g. `#version: 0.2`
        //     _ = lines.next();
        //     while (lines.next()) |line| {
        //         var parts = std.mem.tokenize(u8, line, " ");
        //         const key_part = parts.next() orelse continue;
        //         const value_part = parts.next() orelse continue;
        //
        //         const key = try aallocator.dupe(u8, key_part);
        //         const value = try aallocator.dupe(u8, value_part);
        //
        //         try merges.put(key, value);
        //     }
        // }

        // TODO: maybe add the `pattern_str` as a given argument to the `init`
        // method of `Regex` so that it uses the same patter in the `findAll`,
        // similar to a pattern compilation so that the pattern is re-used (?)
        // TODO: should it also use the `ArenaAllocator`?
        const regex = Regex.init(allocator);
        errdefer regex.deinit();

        return .{
            .vocab = vocab,
            .vocab_r = vocab_r,
            // .merges = merges,
            .regex = regex,
            .arena = arena,
            .allocator = allocator,
        };
    }

    fn pre(self: *Tokenizer, text: []const u8) ![][]const u8 {
        // https://github.com/openai/gpt-2/blob/9b63575ef42771a015060c964af2c3da4cf7c8ab/src/encoder.py#L53
        const pattern = "('s|'t|'re|'ve|'m|'ll|'d| ?[[:alpha:]]+| ?[[:digit:]]+| ?[^[:alnum:][:space:]]+| +[[:space:]]*| +)";
        return try self.regex.findAll(pattern, text);
    }

    pub fn encode(self: *Tokenizer, text: []const u8) ![]const u32 {
        var byte_encoding = std.ArrayList([]const u8).init(self.arena.allocator());
        const matches = try self.pre(text);
        for (matches) |match| {
            const match_encoding = try bytesToUnicode(self.arena.allocator(), match);
            try byte_encoding.append(match_encoding);
        }

        var text_encoding = std.ArrayList(u32).init(self.arena.allocator());
        for (byte_encoding.items) |encoding| {
            if (self.vocab.get(encoding)) |v| {
                try text_encoding.append(v);
            } else {
                var window: usize = 0;
                while (window < encoding.len) {
                    // for ascii returns 1, but for bytes as e.g. `Ġ` the unicode code
                    // point takes 2 bytes in utf-8 (indeed utf-8 characters can be 1-4
                    // bytes)
                    const code_point_length = std.unicode.utf8ByteSequenceLength(encoding[window]) catch {
                        return error.InvalidByteEncoding;
                    };
                    // prevents reading past the end of the buffer
                    if (window + code_point_length > encoding.len) return error.InvalidSplit;

                    const code_point = encoding[window..window+code_point_length];
                    window += code_point_length;

                    if (self.vocab.get(code_point)) |byte_token| {
                        try text_encoding.append(byte_token);
                    } else {
                        std.debug.print("Unknown token: {s}\n", .{code_point});
                        return error.UnknownToken;
                    }
                }
            }
        }
        return text_encoding.toOwnedSlice();
    }

    pub fn deinit(self: *Tokenizer) void {
        self.regex.deinit();
        self.arena.deinit();
    }
};

test "Tokenizer" {
    // https://huggingface.co/openai-community/gpt2/blob/main/vocab.json
    var tokenizer = try Tokenizer.init(std.testing.allocator, "vocab.json");
    defer tokenizer.deinit();

    try std.testing.expectEqual(@as(u32, 50257), tokenizer.vocab.count());
    try std.testing.expect(tokenizer.vocab.contains("<|endoftext|>"));
    try std.testing.expectEqual(@as(u32, 50257), tokenizer.vocab_r.count());
    try std.testing.expect(std.mem.eql(u8, tokenizer.vocab_r.get(@as(u32, 50256)).?, "<|endoftext|>"));

    const text = "Hello, I'm a test string with numbers 123 and symbols @#$!";
    const encoded_text = try tokenizer.encode(text);
    std.debug.print("encoded text {any}\n", .{ encoded_text });
}

const std = @import("std");
const Regex = @import("regex.zig").Regex;
const bytesToUnicode = @import("bytes.zig").bytesToUnicode;
const splitWithDelimiters = @import("split.zig").splitWithDelimiters;

const Pair = struct {
    left: []const u8,
    right: []const u8,
};

const PairContext = struct {
    pub fn hash(self: @This(), pair: Pair) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(pair.left);
        hasher.update(pair.right);
        return hasher.final();
    }

    pub fn eql(self: @This(), a: Pair, b: Pair) bool {
        _ = self;
        return std.mem.eql(u8, a.left, b.left) and std.mem.eql(u8, a.right, b.right);
    }
};

pub const Tokenizer = struct {
    vocab: std.StringHashMap(u32),
    vocab_r: std.AutoHashMap(u32, []const u8),
    merges: std.ArrayList(Pair),
    merges_map: std.HashMap(Pair, u32, PairContext, std.hash_map.default_max_load_percentage),
    regex: Regex,
    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    pub fn init(vocab_path: []const u8, merges_path: []const u8, allocator: std.mem.Allocator) !Tokenizer {
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

        var merges = std.ArrayList(Pair).init(aallocator);
        try merges.ensureTotalCapacity(50000);
        errdefer merges.deinit();

        var merges_map = std.HashMap(Pair, u32, PairContext, std.hash_map.default_max_load_percentage).initContext(aallocator, PairContext{});
        try merges_map.ensureTotalCapacity(50000);
        errdefer merges_map.deinit();

        {
            const merges_content = try std.fs.cwd().readFileAlloc(aallocator, merges_path, 1024 * 1024);
            defer aallocator.free(merges_content);

            var lines = std.mem.tokenize(u8, merges_content, "\n");
            // skip the first line as it contains the `tokenizers` version
            // e.g. `#version: 0.2`
            _ = lines.next();
            var idx: u32 = 0;
            while (lines.next()) |line| {
                var parts = std.mem.tokenize(u8, line, " ");
                const left_part = parts.next() orelse continue;
                const right_part = parts.next() orelse continue;

                const left = try aallocator.dupe(u8, left_part);
                const right = try aallocator.dupe(u8, right_part);
                try merges.append(.{ .left = left, .right = right });
                try merges_map.put(.{ .left = left, .right = right }, idx);
                idx += 1;
            }
        }

        // TODO: maybe add the `pattern_str` as a given argument to the `init`
        // method of `Regex` so that it uses the same patter in the `findAll`,
        // similar to a pattern compilation so that the pattern is re-used (?)
        const regex = Regex.init(allocator);
        errdefer regex.deinit();

        return .{
            .vocab = vocab,
            .vocab_r = vocab_r,
            .merges = merges,
            .merges_map = merges_map,
            .regex = regex,
            .arena = arena,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Tokenizer) void {
        self.regex.deinit();
        self.arena.deinit();
    }

    fn pre(self: *Tokenizer, text: []const u8) ![][]const u8 {
        // https://github.com/openai/gpt-2/blob/9b63575ef42771a015060c964af2c3da4cf7c8ab/src/encoder.py#L53
        const pattern = "('s|'t|'re|'ve|'m|'ll|'d| ?[[:alpha:]]+| ?[[:digit:]]+| ?[^[:alnum:][:space:]]+| +[[:space:]]*| +)";
        return try self.regex.findAll(pattern, text);
    }

    pub fn encode(self: *Tokenizer, text: []const u8) ![]const u32 {
        var byte_encoding = std.ArrayList([]const u8).init(self.arena.allocator());
        defer byte_encoding.deinit();

        // TODO: special_tokens needs to be sorted as it has priority, just like the merges
        const delimiters = &[_][]const u8{ "<|endoftext|>" };
        const splits = try splitWithDelimiters(self.arena.allocator(), text, delimiters);
        for (0..splits.len) |idx| {
            const split = try self.arena.allocator().dupe(u8, splits[idx]);
            if (std.mem.eql(u8, split, "<|endoftext|>")) {
                try byte_encoding.append(split);
            } else {
                const split_null_terminated = try self.arena.allocator().dupeZ(u8, split);
                const matches = try self.pre(split_null_terminated);
                for (matches) |match| {
                    // TODO: most likely redundant, we can keep the code points calculated just
                    // once rather than every time
                    const match_encoding = try bytesToUnicode(self.arena.allocator(), match);
                    try byte_encoding.append(match_encoding);
                }
            }
        }

        var text_encoding = std.ArrayList(u32).init(self.arena.allocator());
        defer text_encoding.deinit();

        for (byte_encoding.items) |encoding| {
            if (self.vocab.get(encoding)) |v| {
                try text_encoding.append(v);
            } else {
                var code_points = std.ArrayList([]const u8).init(self.arena.allocator());
                defer code_points.deinit();

                // split each token into individual unicode code points
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
                    try code_points.append(code_point);
                }

                while (code_points.items.len > 1) {
                    var pairs = std.ArrayList(Pair).init(self.arena.allocator());
                    defer pairs.deinit();

                    for (0..code_points.items.len - 1) |i| {
                        try pairs.append(.{ .left = code_points.items[i], .right = code_points.items[i + 1] });
                    }

                    var best_pair_index: ?usize = null;
                    var best_pair_rank: ?u32 = null;
                    for (pairs.items, 0..) |pair, idx| {
                        if (self.merges_map.get(pair)) |rank| {
                            if (best_pair_rank == null or rank < best_pair_rank.?) {
                                best_pair_rank = rank;
                                best_pair_index = idx;
                            }
                        }
                    }
                    if (best_pair_index) |idx| {
                        const pair = pairs.items[idx];
                        std.debug.print("Merging: '{s}' + '{s}' (rank {d})\n", .{
                            pair.left,
                            pair.right,
                            best_pair_rank.?
                        });
                    }

                    if (best_pair_index == null) break;

                    const merge_idx = best_pair_index.?;
                    const merged_token_len = code_points.items[merge_idx].len + code_points.items[merge_idx + 1].len;
                    const merged_token = try self.arena.allocator().alloc(u8, merged_token_len);

                    std.mem.copyForwards(u8, merged_token[0..code_points.items[merge_idx].len], code_points.items[merge_idx]);
                    std.mem.copyForwards(u8, merged_token[code_points.items[merge_idx].len..], code_points.items[merge_idx + 1]);

                    code_points.items[merge_idx] = merged_token;
                    _ = code_points.orderedRemove(merge_idx + 1);
                }

                for (code_points.items) |token| {
                    if (self.vocab.get(token)) |vocab_id| {
                        try text_encoding.append(vocab_id);
                    } else {
                        return error.TokenNotInVocab;
                    }
                }
            }
        }
        return text_encoding.toOwnedSlice();
    }
};

test "Tokenizer" {
    // https://huggingface.co/openai-community/gpt2/blob/main/vocab.json
    var tokenizer = try Tokenizer.init("vocab.json", "merges.txt", std.testing.allocator);
    defer tokenizer.deinit();

    try std.testing.expectEqual(@as(u32, 50257), tokenizer.vocab.count());
    try std.testing.expect(tokenizer.vocab.contains("<|endoftext|>"));
    try std.testing.expectEqual(@as(u32, 50257), tokenizer.vocab_r.count());
    try std.testing.expect(std.mem.eql(u8, tokenizer.vocab_r.get(@as(u32, 50256)).?, "<|endoftext|>"));

    const text = "Hello, I'm a test string with numbers 123 and symbols @#$!<|endoftext|>";
    const encoded_text = try tokenizer.encode(text);
    try std.testing.expectEqualSlices(u32, encoded_text, &[_]u32{
        15496, 11, 314, 1101, 257, 1332, 4731, 351,
        3146, 17031, 290, 14354, 2488, 29953, 0, 50256
    });
}

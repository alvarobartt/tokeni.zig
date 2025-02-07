// TODO: a bunch of potential improvements here, among those adding a `from_pretrained`
// like method to avoid having to pull the files locally, and improved special_token
// detection, among many other improvements such as extending the tests or adding
// actual documentation based on Zig standards rather than just code comments here
// and there

const std = @import("std");
const Regex = @import("regex.zig").Regex;
const splitSpecialTokens = @import("split.zig").splitSpecialTokens;
const Pair = @import("pair.zig").Pair;
const PairContext = @import("pair.zig").PairContext;
const bytesToTokens = @import("byte_encoding.zig").bytesToTokens;
const tokensToBytes = @import("byte_decoding.zig").tokensToBytes;

pub const Tokenizer = struct {
    const Self = @This();

    vocab: std.StringHashMap(u21),
    vocab_r: std.AutoHashMap(u21, []const u8),
    merges: std.ArrayList(Pair),
    merges_map: std.HashMap(Pair, u21, PairContext, std.hash_map.default_max_load_percentage),
    regex: Regex,
    special_tokens: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(vocab_path: []const u8, merges_path: []const u8, pattern: []const u8, special_tokens: std.ArrayList([]const u8), allocator: std.mem.Allocator) !Self {
        var vocab = std.StringHashMap(u21).init(allocator);
        // TODO: maybe this can be pulled from https://huggingface.co/openai-community/gpt2/blob/main/config.json#L30
        try vocab.ensureTotalCapacity(50257);
        errdefer vocab.deinit();

        var vocab_r = std.AutoHashMap(u21, []const u8).init(allocator);
        try vocab_r.ensureTotalCapacity(50257);
        errdefer vocab_r.deinit();

        {
            // https://ziglang.org/documentation/master/std/#std.fs
            const vocab_content = try std.fs.cwd().readFileAlloc(allocator, vocab_path, 1024 * 1024);
            defer allocator.free(vocab_content);

            // https://ziglang.org/documentation/master/std/#std.json
            var json_tree = try std.json.parseFromSlice(std.json.Value, allocator, vocab_content, .{});
            defer json_tree.deinit();

            const root = json_tree.value;
            if (root == .object) {
                var it = root.object.iterator();
                while (it.next()) |entry| {
                    // as the key is a `[]const u8` i.e. not a primitive type, we need
                    // to copy it explicitly as otherwise we're just storing the pointer
                    // which can easily go out of scope and leave the `HashMap` invalid
                    const key = try allocator.dupe(u8, entry.key_ptr.*);
                    // on the other hand for primitive types we don't need to explicitly
                    // copy or dupe those, as those have a fixed size and are easy to copy
                    // and move
                    const value = @as(u21, @intCast(entry.value_ptr.*.integer));
                    try vocab.put(key, value);
                    try vocab_r.put(value, key);
                }
            }
        }

        var merges = std.ArrayList(Pair).init(allocator);
        try merges.ensureTotalCapacity(50000);
        errdefer merges.deinit();

        var merges_map = std.HashMap(Pair, u21, PairContext, std.hash_map.default_max_load_percentage).initContext(allocator, PairContext{});
        try merges_map.ensureTotalCapacity(50000);
        errdefer merges_map.deinit();

        {
            const merges_content = try std.fs.cwd().readFileAlloc(allocator, merges_path, 1024 * 1024);
            defer allocator.free(merges_content);

            var lines = std.mem.tokenize(u8, merges_content, "\n");
            // skip the first line as it contains the `tokenizers` version
            // e.g. `#version: 0.2`
            _ = lines.next();
            var idx: u21 = 0;
            while (lines.next()) |line| {
                var parts = std.mem.tokenize(u8, line, " ");
                const left_part = parts.next() orelse continue;
                const right_part = parts.next() orelse continue;

                const left = try allocator.dupe(u8, left_part);
                const right = try allocator.dupe(u8, right_part);
                try merges.append(.{ .left = left, .right = right });
                try merges_map.put(.{ .left = left, .right = right }, idx);
                idx += 1;
            }
        }

        const regex = try Regex.init(allocator, pattern);
        errdefer regex.deinit();

        return .{
            .vocab = vocab,
            .vocab_r = vocab_r,
            .merges = merges,
            .merges_map = merges_map,
            .regex = regex,
            .special_tokens = special_tokens,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var vocab_it = self.vocab.iterator();
        while (vocab_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.vocab.deinit();
        self.vocab_r.deinit();

        for (self.merges.items) |merge| {
            self.allocator.free(merge.left);
            self.allocator.free(merge.right);
        }
        self.merges.deinit();
        self.merges_map.deinit();

        self.regex.deinit();
    }

    // TODO: here just temporarily in case we want to debug the pretokenizer
    // itself, to be later on renamed to pretokenize_str or something closer to
    // the Rust counterpart
    fn pre(self: *Self, text: []const u8) ![][]const u8 {
        return try self.regex.findAll(text);
    }

    pub fn encode(self: *Self, text: []const u8) ![]const u21 {
        const allocator = self.allocator;

        var byte_encoding = std.ArrayList([]const u8).init(allocator);
        defer {
            for (byte_encoding.items) |item| allocator.free(item);
            byte_encoding.deinit();
        }

        // TODO: I'm highly confident that the special token discovery can be
        // highly improved as now it feels that we discover those and separate
        // those from the rest, and then we loop over the splits again and try 
        // to check which out of the existing special token it is (if any)
        const splits = try splitSpecialTokens(allocator, text, self.special_tokens.items);
        defer allocator.free(splits);

        for (splits) |split| {
            const is_special_token = blk: {
                for (self.special_tokens.items) |special| {
                    if (std.mem.eql(u8, split, special)) break :blk true;
                }
                break :blk false;
            };

            if (is_special_token) {
                const owned = try allocator.dupe(u8, split);
                try byte_encoding.append(owned);
            } else {
                const split_z = try allocator.dupeZ(u8, split);
                defer allocator.free(split_z);
                
                const matches = try self.pre(split_z);
                defer {
                    for (matches) |m| allocator.free(m);
                    allocator.free(matches);
                }
                
                for (matches) |match| {
                    const owned_match = try allocator.dupe(u8, match);
                    defer allocator.free(owned_match);

                    const match_encoding = try bytesToTokens(allocator, owned_match);
                    try byte_encoding.append(match_encoding);
                }
            }
        }
        // TODO(follow-up): until here should be improved for sure!

        var text_encoding = std.ArrayList(u21).init(allocator);
        errdefer text_encoding.deinit();

        for (byte_encoding.items) |encoding| {
            if (self.vocab.get(encoding)) |id| {
                try text_encoding.append(id);
                continue;
            }

            var code_points = std.ArrayList([]const u8).init(allocator);
            defer {
                for (code_points.items) |code_point| allocator.free(code_point);
                code_points.deinit();
            }

            // split each token into individual unicode code points
            var pos: usize = 0;
            while (pos < encoding.len) {
                // for ascii returns 1, but for bytes as e.g. `Ġ` the unicode code
                // point takes 2 bytes in utf-8 (indeed utf-8 characters can be 1-4
                // bytes)
                const len = std.unicode.utf8ByteSequenceLength(encoding[pos]) catch {
                    return error.InvalidUtf8;
                };
                // prevents reading past the end of the buffer
                if (pos + len > encoding.len) return error.InvalidUtf8;
                
                const code_point = try allocator.dupe(u8, encoding[pos..pos+len]);
                try code_points.append(code_point);
                pos += len;
            }

            while (code_points.items.len > 1) {
                var best_idx: ?usize = null;
                var best_rank: u21 = std.math.maxInt(u21);
                
                for (0..code_points.items.len - 1) |i| {
                    const pair = Pair{
                        .left = code_points.items[i],
                        .right = code_points.items[i+1]
                    };
                    
                    if (self.merges_map.get(pair)) |rank| {
                        if (rank < best_rank) {
                            best_rank = rank;
                            best_idx = i;
                        }
                    }
                }

                const merge_idx = best_idx orelse break;

                const merged_pair = try allocator.alloc(u8, 
                    code_points.items[merge_idx].len + code_points.items[merge_idx+1].len
                );

                std.mem.copyForwards(u8, merged_pair[0..code_points.items[merge_idx].len], code_points.items[merge_idx]);
                std.mem.copyForwards(u8, merged_pair[code_points.items[merge_idx].len..], code_points.items[merge_idx+1]);

                allocator.free(code_points.items[merge_idx]);
                allocator.free(code_points.items[merge_idx+1]);

                code_points.items[merge_idx] = merged_pair;
                _ = code_points.orderedRemove(merge_idx+1);
            }

            for (code_points.items) |token| {
                try text_encoding.append(
                    self.vocab.get(token) orelse return error.TokenNotInVocab
                );
            }
        }

        return text_encoding.toOwnedSlice();
    }

    pub fn decode(self: Self, input_ids: []const u21) ![]const u8 {
        var buffer = std.ArrayList(u8).init(self.allocator);
        errdefer buffer.deinit();

        for (input_ids) |id| {
            const token = self.vocab_r.get(id) orelse return error.InvalidTokenId;
            // token is not a single token per se e.g. "ĠI", can be a token, but we
            // need to split the different unicode characters being "Ġ" taking 2 bytes
            // in this case and "I" taking 1 byte; then for "Ġ" we should check the reversed
            // mapping actual UTF-8 value and append it into the buffer
            const decoded = try tokensToBytes(self.allocator, token);
            defer self.allocator.free(decoded);

            try buffer.appendSlice(decoded);
        }
        return buffer.toOwnedSlice();
    }
};

test "Tokenizer" {
    const allocator = std.testing.allocator;

    // TODO: special token initialization can also be read from the `tokenizer_config.json`
    var special_tokens = std.ArrayList([]const u8).init(allocator);
    defer special_tokens.deinit();
    try special_tokens.append("<|endoftext|>");

    // https://huggingface.co/openai-community/gpt2/blob/main/vocab.json
    // https://huggingface.co/openai-community/gpt2/blob/main/merges.txt
    var tokenizer = try Tokenizer.init(
        "vocab.json",
        "merges.txt",
        "('s|'t|'re|'ve|'m|'ll|'d| ?[[:alpha:]]+| ?[[:digit:]]+| ?[^[:alnum:][:space:]]+| +[[:space:]]*| +)",
        special_tokens,
        allocator,
    );
    defer tokenizer.deinit();

    try std.testing.expectEqual(@as(u21, 50257), tokenizer.vocab.count());
    try std.testing.expect(tokenizer.vocab.contains("<|endoftext|>"));
    try std.testing.expectEqual(@as(u21, 50257), tokenizer.vocab_r.count());
    try std.testing.expect(std.mem.eql(u8, tokenizer.vocab_r.get(@as(u21, 50256)).?, "<|endoftext|>"));

    const text = "Hello, I'm a test string with numbers 123 and symbols @#$!<|endoftext|>";
    const encoding = try tokenizer.encode(text);
    defer tokenizer.allocator.free(encoding);

    try std.testing.expectEqualSlices(u21, encoding, &[_]u21{
        15496, 11, 314, 1101, 257, 1332, 4731, 351,
        3146, 17031, 290, 14354, 2488, 29953, 0, 50256
    });

    const decoding = try tokenizer.decode(encoding);
    defer tokenizer.allocator.free(decoding);

    try std.testing.expectEqualStrings(text, decoding);
}

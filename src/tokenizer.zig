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

    pub fn init(tokenizer_file: []const u8, allocator: std.mem.Allocator) !Self {
        var file = try std.fs.cwd().openFile(tokenizer_file, .{});
        defer file.close();

        const stat = try file.stat();
        const buffer = try allocator.alloc(u8, stat.size);
        defer allocator.free(buffer);

        _ = try file.reader().read(buffer);

        var json = try std.json.parseFromSlice(std.json.Value, allocator, buffer, .{});
        defer json.deinit();

        var vocab = std.StringHashMap(u21).init(allocator);
        errdefer vocab.deinit();
        var vocab_r = std.AutoHashMap(u21, []const u8).init(allocator);
        errdefer vocab_r.deinit();

        var merges = std.ArrayList(Pair).init(allocator);
        errdefer merges.deinit();
        var merges_map = std.HashMap(Pair, u21, PairContext, std.hash_map.default_max_load_percentage).initContext(allocator, PairContext{});
        errdefer merges_map.deinit();

        var special_tokens = std.ArrayList([]const u8).init(allocator);
        errdefer special_tokens.deinit();

        const model = json.value.object.get("model").?;
        if (model == .object) {
            const vocab_json = model.object.get("vocab").?;
            if (vocab_json == .object) {
                const obj = vocab_json.object;
                var i: usize = 0;
                while (i < obj.count()) : (i += 1) {
                    const key = try allocator.dupe(u8, obj.keys()[i]);
                    const value = @as(u21, @intCast(obj.values()[i].integer));

                    try vocab.put(key, value);
                    try vocab_r.put(value, key);
                }
            }

            const merges_json = model.object.get("merges").?;
            if (merges_json == .array) {
                var idx: u21 = 0;
                for (merges_json.array.items) |merge| {
                    const content = merge.string;
                    var splits_it = std.mem.split(u8, content, " ");

                    const split_left = splits_it.next() orelse continue;
                    const left = try allocator.dupe(u8, split_left);

                    const split_right = splits_it.next() orelse continue;
                    const right = try allocator.dupe(u8, split_right);

                    try merges.append(.{ .left = left, .right = right });
                    try merges_map.put(.{ .left = left, .right = right }, idx);
                    idx += 1;
                }
            }
        }

        const added_tokens = json.value.object.get("added_tokens").?;
        if (added_tokens == .array) {
            for (added_tokens.array.items) |added_token| {
                const is_special = added_token.object.get("special").?;
                const content = added_token.object.get("content").?;
                if (is_special == .bool and content == .string) {
                    if (is_special.bool == true) {
                        const special_token = try allocator.dupe(u8, content.string);
                        try special_tokens.append(special_token);
                    }
                }
            }
        }

        const regex = try Regex.init(allocator, "('s|'t|'re|'ve|'m|'ll|'d| ?[[:alpha:]]+| ?[[:digit:]]+| ?[^[:alnum:][:space:]]+| +[[:space:]]*| +)");
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

        for (self.special_tokens.items) |item| {
            self.allocator.free(item);
        }
        self.special_tokens.deinit();

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

    // https://huggingface.co/openai-community/gpt2/blob/main/tokenizer.json
    var tokenizer = try Tokenizer.init("tokenizer.json", allocator);
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

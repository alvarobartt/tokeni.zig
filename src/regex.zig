const std = @import("std");
const c = @cImport({
    @cInclude("regex.h");
});

pub const Regex = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    regex: c.regex_t,

    pub fn init(allocator: std.mem.Allocator, pattern: []const u8) !Self {
        // https://www.gnu.org/software/libc/manual/html_node/POSIX-Regexp-Compilation.html#index-regex_005ft
        var regex: c.regex_t = undefined;
        // https://www.gnu.org/software/libc/manual/html_node/POSIX-Regexp-Compilation.html#index-regcomp
        // https://www.gnu.org/software/libc/manual/html_node/Flags-for-POSIX-Regexps.html#index-REG_005fEXTENDED
        const compile_result = c.regcomp(&regex, pattern.ptr, c.REG_EXTENDED);
        if (compile_result != 0) {
            return error.RegexCompilationFailed;
        }

        return Self{
            .allocator = allocator,
            .regex = regex,
        };
    }

    pub fn deinit(self: Self) void {
        // https://www.gnu.org/software/libc/manual/html_node/Regexp-Cleanup.html#index-regfree
        c.regfree(@constCast(&self.regex));
    }

    pub fn findAll(self: *Self, text: []const u8) ![][]const u8 {
        const allocator = self.allocator;

        var buffer: ?[]u8 = null;
        defer if (buffer) |b| allocator.free(b);

        // c expects null-terminated strings so this is just an additional harmless check
        const text_null_terminated = if (text.len == 0 or text[text.len - 1] != 0) blk: {
            buffer = try allocator.alloc(u8, text.len + 1);
            std.mem.copyForwards(u8, buffer.?[0..text.len], text);
            buffer.?[text.len] = 0;
            break :blk buffer.?;
        } else text;

        var matches = std.ArrayList([]const u8).init(allocator);
        errdefer {
            for (matches.items) |m| allocator.free(m);
            matches.deinit();
        }

        var offset: usize = 0;
        while (offset < text.len) {
            // https://www.gnu.org/software/libc/manual/html_node/Regexp-Subexpressions.html#index-regmatch_005ft
            var pmatch: [1]c.regmatch_t = undefined;
            // https://www.gnu.org/software/libc/manual/html_node/Matching-POSIX-Regexps.html#index-regexec
            const exec_result = c.regexec(&self.regex, text_null_terminated[offset..].ptr, 1, &pmatch, 0);

            if (exec_result != 0) break;

            const start = offset + @as(usize, @intCast(pmatch[0].rm_so));
            const end = offset + @as(usize, @intCast(pmatch[0].rm_eo));

            const match_text = try allocator.dupe(u8, text_null_terminated[start..end]);
            errdefer allocator.free(match_text);

            try matches.append(match_text);
            offset = end;
        }

        return matches.toOwnedSlice();
    }
};

test "Regex.findAll" {
    const allocator = std.testing.allocator;

    // https://github.com/openai/gpt-2/blob/9b63575ef42771a015060c964af2c3da4cf7c8ab/src/encoder.py#L53
    const pattern = "('s|'t|'re|'ve|'m|'ll|'d| ?[[:alpha:]]+| ?[[:digit:]]+| ?[^[:alnum:][:space:]]+| +[[:space:]]*| +)";
    var regex = try Regex.init(allocator, pattern);
    defer regex.deinit();

    const text = "Hello, I'm a test string with numbers 123 and symbols @#$!";
    const matches = try regex.findAll(text);
    defer {
        for (matches) |m| allocator.free(m);
        allocator.free(matches);
    }

    try std.testing.expectEqual(@as(usize, 13), matches.len);
    try std.testing.expectEqualStrings("Hello", matches[0]);
    try std.testing.expectEqualStrings(" I", matches[2]);
    try std.testing.expectEqualStrings("'m", matches[3]);
    try std.testing.expectEqualStrings(" @#$!", matches[12]);
}

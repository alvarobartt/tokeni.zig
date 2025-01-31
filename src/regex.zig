const std = @import("std");
const c = @cImport({
    @cInclude("regex.h");
});

pub const Regex = struct {
    arena: std.heap.ArenaAllocator,
    regex: c.regex_t,

    pub fn init(allocator: std.mem.Allocator, pattern: []const u8) !Regex {
        var arena = std.heap.ArenaAllocator.init(allocator);

        // https://www.gnu.org/software/libc/manual/html_node/POSIX-Regexp-Compilation.html#index-regex_005ft
        var regex: c.regex_t = undefined;
        // https://www.gnu.org/software/libc/manual/html_node/POSIX-Regexp-Compilation.html#index-regcomp
        // https://www.gnu.org/software/libc/manual/html_node/Flags-for-POSIX-Regexps.html#index-REG_005fEXTENDED
        const compile_result = c.regcomp(&regex, pattern.ptr, c.REG_EXTENDED);
        if (compile_result != 0) {
            arena.deinit();
            return error.RegexCompilationFailed;
        }

        return Regex{
            .arena = arena,
            .regex = regex,
        };
    }

    pub fn deinit(self: Regex) void {
        // https://www.gnu.org/software/libc/manual/html_node/Regexp-Cleanup.html#index-regfree
        c.regfree(@constCast(&self.regex));
        self.arena.deinit();
    }

    pub fn findAll(self: *Regex, text: []const u8) ![][]const u8 {
        // c expects null-terminated strings so this is just an additional harmless check
        const text_null_terminated: []const u8 = if (text.len == 0 or text[text.len - 1] != 0) block: {
            var buffer = try self.arena.allocator().alloc(u8, text.len + 1);
            std.mem.copyForwards(u8, buffer[0..text.len], text);
            buffer[text.len] = 0;
            break :block buffer;
        } else text;

        var matches = std.ArrayList([]const u8).init(self.arena.allocator());
        errdefer matches.deinit();

        var offset: usize = 0;
        while (offset < text.len) {
            // https://www.gnu.org/software/libc/manual/html_node/Regexp-Subexpressions.html#index-regmatch_005ft
            var pmatch: [1]c.regmatch_t = undefined;
            // https://www.gnu.org/software/libc/manual/html_node/Matching-POSIX-Regexps.html#index-regexec
            const exec_result = c.regexec(&self.regex, text_null_terminated[offset..].ptr, 1, &pmatch, 0);

            if (exec_result != 0) break;

            const start = offset + @as(usize, @intCast(pmatch[0].rm_so));
            const end = offset + @as(usize, @intCast(pmatch[0].rm_eo));
            try matches.append(text_null_terminated[start..end]);

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

    try std.testing.expectEqual(@as(usize, 13), matches.len);
    try std.testing.expectEqualStrings("Hello", matches[0]);
    try std.testing.expectEqualStrings(" I", matches[2]);
    try std.testing.expectEqualStrings("'m", matches[3]);
    try std.testing.expectEqualStrings(" @#$!", matches[12]);
}

const std = @import("std");
const c = @cImport({
    @cInclude("regex.h");
});

pub const Regex = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Regex {
        return Regex{ .allocator = allocator };
    }

    pub fn findAll(self: *Regex, pattern: []const u8, text: []const u8) ![][]const u8 {
        // https://www.gnu.org/software/libc/manual/html_node/POSIX-Regexp-Compilation.html#index-regex_005ft
        var regex: c.regex_t = undefined;
        // https://www.gnu.org/software/libc/manual/html_node/POSIX-Regexp-Compilation.html#index-regcomp
        // https://www.gnu.org/software/libc/manual/html_node/Flags-for-POSIX-Regexps.html#index-REG_005fEXTENDED
        const compile_result = c.regcomp(&regex, pattern.ptr, c.REG_EXTENDED);
        // https://www.gnu.org/software/libc/manual/html_node/Regexp-Cleanup.html#index-regfree
        defer c.regfree(&regex);

        if (compile_result != 0) {
            return error.RegexCompilationFailed;
        }

        var matches = std.ArrayList([]const u8).init(self.allocator);
        errdefer matches.deinit();

        var offset: usize = 0;
        while (offset < text.len) {
            // https://www.gnu.org/software/libc/manual/html_node/Regexp-Subexpressions.html#index-regmatch_005ft
            var pmatch: [1]c.regmatch_t = undefined;
            // https://www.gnu.org/software/libc/manual/html_node/Matching-POSIX-Regexps.html#index-regexec
            const exec_result = c.regexec(&regex, text[offset..].ptr, 1, &pmatch, 0);

            if (exec_result != 0) break;

            const start = offset + @as(usize, @intCast(pmatch[0].rm_so));
            const end = offset + @as(usize, @intCast(pmatch[0].rm_eo));
            try matches.append(text[start..end]);

            offset = end;
        }

        return matches.toOwnedSlice();
    }
};

test "Regex.findAll" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var regex = Regex.init(allocator);

    // https://github.com/openai/gpt-2/blob/9b63575ef42771a015060c964af2c3da4cf7c8ab/src/encoder.py#L53
    const pattern = "('s|'t|'re|'ve|'m|'ll|'d| ?[[:alpha:]]+| ?[[:digit:]]+| ?[^[:alnum:][:space:]]+| +[[:space:]]*| +)";
    const text = "Hello, I'm a test string with numbers 123 and symbols @#$!";

    const matches = try regex.findAll(pattern, text);
    defer allocator.free(matches);

    try std.testing.expectEqual(@as(usize, 13), matches.len);
    try std.testing.expectEqualStrings("Hello", matches[0]);
    try std.testing.expectEqualStrings(" I", matches[2]);
    try std.testing.expectEqualStrings("'m", matches[3]);
    try std.testing.expectEqualStrings(" @#$!", matches[12]);
}

const std = @import("std");

pub const Pair = struct {
    left: []const u8,
    right: []const u8,
};

pub const PairContext = struct {
    pub fn hash(self: @This(), pair: Pair) u64 {
        _ = self; // autofix
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(pair.left);
        hasher.update(pair.right);
        return hasher.final();
    }

    pub fn eql(self: @This(), a: Pair, b: Pair) bool {
        _ = self; // autofix
        return std.mem.eql(u8, a.left, b.left) and std.mem.eql(u8, a.right, b.right);
    }
};

const std = @import("std");

// Pair is used to store the different parts of each merge
pub const Pair = struct {
    left: []const u8,
    right: []const u8,
};

// PairContext just adds the context for the Pair, so that we can create a
// HashMap with the Pair being the key thanks to the `hash` method, as well as
// comparing values `eql` method
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

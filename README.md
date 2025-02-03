# tokeni.zig

`tokeni.zig` (stands for tokenizer + Zig) is a minimal implementation of a Byte
Pair Encoding (BPE) tokenizer in Zig.

> [!WARNING]
> This implementation is currently a learning project for exploring Zig and
> tokenizer internals (particularly BPE used in models like e.g. DeepSeek R1).
> Expect rough edges, contributions are more than welcomed!

## Installation

Requires Zig 0.13.0+. Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .tokeni = .{
        .url = "https://github.com/alvarobartt/tokeni.zig/archive/refs/tags/v0.0.1.tar.gz",
        .hash = "[PACKAGE_HASH]",
    },
},
```

And then `git submodule add https://github.com/alvarobartt/tokeni.zig libs/tokeni`.

For other platforms or build setups, refer to [Zig Build System](https://ziglang.org/learn/build-system/).

## Usage

```zig
const std = @import("std");
const tokeni = @import("tokeni");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var special_tokens = std.ArrayList([]const u8).init(allocator);
    defer special_tokens.deinit();
    try special_tokens.append("<|endoftext|>");

    // https://huggingface.co/openai-community/gpt2
    var tokenizer = try tokeni.Tokenizer.init(
        "vocab.json",
        "merges.txt",
        "('s|'t|'re|'ve|'m|'ll|'d| ?[[:alpha:]]+| ?[[:digit:]]+| ?[^[:alnum:][:space:]]+| +[[:space:]]*| +)",
        special_tokens,
        allocator,
    );
    defer tokenizer.deinit();

    const text = "Hello, I'm a test string with numbers 123 and symbols @#$!<|endoftext|>";
    const encoding = try tokenizer.encode(text);
    defer allocator.free(encoding);

    std.debug.print("Encoded tokens: {any}\n", .{encoding});
}
```

## What's next?

Mainly making the codebase robust enough, and pushing the performance even further,
compare this with other solutions such as `tiktoken` or `tokenizers`, maybe eventually
create Python bindings, add a `from_pretrained` like method to use any BPE-based
tokenizer from the Hugging Face Hub, add more documentation and tests, etc.

TL;DR a BUNCH of things, but always with learning purposes in mind!

So I'd say that I'll be committing to this repository somehow frequently until I
feel confident with Zig, and once I push the implementation as far as I can.

---

Programming should be fun, and this is fun to me!

# tokeni.zig

`tokeni.zig` (stands for tokenizer + Zig) is a minimal implementation of a Byte
Pair Encoding (BPE) tokenizer in Zig.

> [!WARNING]
> This implementation is currently a learning project for exploring Zig and
> tokenizer internals (particularly BPE used in models like e.g. GPT-2).
> Expect rough edges, contributions are more than welcomed!

## Usage

First you need to download the `tokenizer.json` file from the Hugging Face Hub
at [`openai-community/gpt2`](https://huggingface.co/openai-community/gpt2).

```zig
const std = @import("std");
const tokeni = @import("tokeni");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // https://huggingface.co/openai-community/gpt2/tree/main/tokenizer.json
    var tokenizer = try tokeni.Tokenizer.init("tokenizer.json", allocator);
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

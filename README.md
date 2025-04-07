# bpe.zig

`bpe.zig` is a minimal implementation of a Byte Pair Encoding (BPE) tokenizer in Zig.

> [!WARNING]
> This implementation is currently an educational project for exploring Zig and
> tokenizer internals (particularly BPE used in models like e.g. GPT-2).

## Usage

First you need to download the `tokenizer.json` file from the Hugging Face Hub
at [`openai-community/gpt2`](https://huggingface.co/openai-community/gpt2).

```zig
const std = @import("std");
const Tokenizer = @import("bpe.Tokenizer");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // https://huggingface.co/openai-community/gpt2/tree/main/tokenizer.json
    var tokenizer = try Tokenizer.init("tokenizer.json", allocator);
    defer tokenizer.deinit();

    const text = "Hello, I'm a test string with numbers 123 and symbols @#$!<|endoftext|>";
    const encoding = try tokenizer.encode(text);
    defer allocator.free(encoding);

    std.debug.print("Encoded tokens: {any}\n", .{encoding});
}
```

## License

This project is licensed under either of the following licenses, at your option:

- [Apache License, Version 2.0](LICENSE-APACHE)
- [MIT License](LICENSE-MIT)

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in this project by you, as defined in the Apache-2.0 license, shall
be dual licensed as above, without any additional terms or conditions.

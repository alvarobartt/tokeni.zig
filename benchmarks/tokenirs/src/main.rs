use clap::Parser;
use std::fs;
use std::time::Instant;
use tokenizers::Tokenizer;

#[derive(Parser)]
struct Args {
    input_file: String,
}

fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let args = Args::parse();

    let tokenizer = Tokenizer::from_pretrained("gpt2", None)?;

    let mut input_text = fs::read_to_string(&args.input_file)?;
    input_text.push_str("<|endoftext|>");

    let input_text = input_text.as_str();
    let _ = tokenizer.encode(input_text, true)?;

    let iterations = 10;
    let start_time = Instant::now();

    for _ in 0..iterations {
        let encoded = tokenizer.encode(input_text, true)?;

        if let Some(last_token) = encoded.get_ids().last() {
            assert_eq!(*last_token, 50256, "Last token is not 50256!");
        }
    }

    let elapsed_time = start_time.elapsed();
    let total_ns = elapsed_time.as_nanos();
    let total_ms = elapsed_time.as_millis() as f64;

    let ns_per_op = total_ns as f64 / iterations as f64;
    let ms_per_op = ns_per_op / 1_000_000.0;
    let s_per_op = ms_per_op / 1_000.0;

    let total_bytes = input_text.len();
    let throughput_mb_s =
        (total_bytes as f64 * iterations as f64) / (elapsed_time.as_secs_f64() * 1024.0 * 1024.0);

    println!(
        "Benchmark results:\n\
         Iterations: {}\n\
         Total time: {:.2}ms\n\
         Time per encode: {:.2}ms ({:.4}s)\n\
         Throughput: {:.2}MB/s",
        iterations, total_ms, ms_per_op, s_per_op, throughput_mb_s,
    );

    Ok(())
}

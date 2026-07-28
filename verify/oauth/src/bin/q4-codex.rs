use cc_trace_oauth_verify::{Provider, run_from_cli};

fn main() {
    if let Err(error) = run_from_cli(Provider::Codex) {
        eprintln!("Q4 Codex 验证已停止：{error}");
        std::process::exit(1);
    }
}

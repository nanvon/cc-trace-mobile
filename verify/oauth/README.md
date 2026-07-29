# Q4 OAuth 验证脚手架

这是 [OAuth 可行性验证](../../docs/OAuth可行性验证.md) 中 Q4 的独立 Rust crate。它只做：

```text
系统浏览器授权 → loopback 回调 → code 换 token → usage 请求 → 证据留存
```

它不是 Flutter 应用的一部分，也不会复用为未来 Dart 应用代码；不做额度归一化、状态机、
缓存、持久化或任何界面。

## 执行顺序

先以**默认的完整 scope**跑通两家，再进行 Q4 文档 §4.4 规定的 scope 削减实验。不要把反复
请求直到 429 的限流试探交给本脚手架自动执行；那必须在全部 scope 实验结束后单独、人工控制地做。

Claude 的 5 小时 `is_active` 观察也必须先开始：记下开始时间，停止使用 Claude Code 对话，5 小时后
再运行一次 `q4-claude`。

```bash
cargo run --manifest-path verify/oauth/Cargo.toml --bin q4-codex
cargo run --manifest-path verify/oauth/Cargo.toml --bin q4-claude
```

基线完成后，削减 scope 时只替换 `--scope` 的值、每次重走完整授权；例如：

```bash
cargo run --manifest-path verify/oauth/Cargo.toml --bin q4-claude -- --scope "user:profile user:sessions:claude_code"
```

不要在完成完整 scope 基线前使用这个参数。

每次运行会在系统默认浏览器打开 Provider 登录页。完成自己的账号登录后，浏览器会回到本地 loopback
server；终端只输出非敏感的状态、token 字段结构、JWT 的 `exp` 与 `account_id: present / absent`。

## 证据留存

- usage 响应体和去除 `Set-Cookie` 的响应头会写进 `fixtures/raw/`，该目录已被 Git 忽略，文件权限为仅当前用户可读写。
- token 响应、access token、refresh token、id token、authorization code 和 Authorization 请求头永不写盘、永不输出。
- 将入库 fixture 前必须人工检查 `fixtures/raw/`，用白名单过滤后再放进 `fixtures/providers/`；不要用黑名单删除字段。
- 每次采集后把文件名、日期、Provider、账号类型、scope 与结果补到 [`fixtures/采集记录.md`](../../fixtures/采集记录.md)。

使用自己的账号验证；脚手架只请求 usage，不读取或上传对话内容。

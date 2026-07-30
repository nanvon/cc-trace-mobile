//! Q4 的最小 OAuth 验证脚手架。
//!
//! 安全边界：token、authorization code 与 Authorization 请求头只存在于内存；本 crate
//! 只会把 usage 响应和移除了 Set-Cookie 的响应头写入已忽略的 `fixtures/raw/`。

use std::{
    collections::BTreeMap,
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    net::{TcpListener, TcpStream},
    path::{Path, PathBuf},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use base64::{
    Engine as _,
    engine::general_purpose::{URL_SAFE, URL_SAFE_NO_PAD},
};
use rand::{RngCore, rngs::OsRng};
use reqwest::{
    StatusCode,
    blocking::Client,
    header::{ACCEPT, AUTHORIZATION, HeaderMap, USER_AGENT},
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use url::Url;

const CALLBACK_TIMEOUT: Duration = Duration::from_secs(5 * 60);
const OPENAI_AUTH_CLAIM_NAMESPACE: &str = "https://api.openai.com/auth";

/// Q4 可验证的 Provider。
#[derive(Clone, Copy)]
pub enum Provider {
    Codex,
    Claude,
}

#[derive(Clone, Copy)]
struct ProviderConfig {
    display_name: &'static str,
    slug: &'static str,
    authorize_endpoint: &'static str,
    token_endpoint: &'static str,
    usage_endpoint: &'static str,
    client_id: &'static str,
    scopes: &'static str,
    callback_path: &'static str,
    ports: &'static [u16],
}

struct Loopback {
    listener: TcpListener,
    redirect_uri: String,
}

struct Callback {
    code: String,
}

struct TokenSet {
    access_token: String,
    id_token: Option<String>,
    account_id: Option<String>,
    account_id_source: Option<&'static str>,
}

struct UsageResponse {
    status: StatusCode,
    headers: HeaderMap,
    body: String,
}

/// 从命令行执行 Q4。只接受 `--scope <space-separated scopes>`；省略时使用完整 scope。
pub fn run_from_cli(provider: Provider) -> Result<(), String> {
    let arguments = std::env::args().skip(1).collect::<Vec<_>>();
    if arguments == ["--help"] || arguments == ["-h"] {
        println!(
            "用法：cargo run --bin q4-{} [--scope \"scope one scope two\"]",
            provider_config(provider).slug
        );
        println!(
            "省略 --scope 时使用文档规定的完整 scope；仅在完整 scope 基线成功后，才允许做削减实验。"
        );
        return Ok(());
    }
    let scope_override = match arguments.as_slice() {
        [] => None,
        [flag, scope] if flag == "--scope" && !scope.trim().is_empty() => Some(scope.as_str()),
        _ => return Err("参数无效；仅支持 --scope <以空格分隔的 scope>。".to_owned()),
    };
    run(provider, scope_override)
}

/// 执行一次 Q4 验证。省略 scope 时使用完整 scope；削减实验必须晚于完整 scope 基线。
pub fn run(provider: Provider, scope_override: Option<&str>) -> Result<(), String> {
    let config = provider_config(provider);
    let scope = scope_override.unwrap_or(config.scopes);
    let loopback = bind_loopback(config)?;
    let state = random_base64url(32);
    let verifier = random_base64url(64);
    let authorize_url =
        build_authorize_url(config, &loopback.redirect_uri, scope, &state, &verifier)?;

    println!(
        "Q4 {}：本地回调已监听，scope：{}；正在用系统默认浏览器打开 Provider 登录页。",
        config.display_name, scope
    );
    webbrowser::open(authorize_url.as_str())
        .map_err(|_| "无法打开系统默认浏览器；验证未发送任何 token 请求。".to_owned())?;

    let callback = wait_for_callback(&loopback.listener, &state, CALLBACK_TIMEOUT)?;
    let token_response = exchange_code(
        config,
        &loopback.redirect_uri,
        &verifier,
        &state,
        &callback.code,
    )?;
    let tokens = parse_tokens(config, &token_response)?;

    print_token_evidence(config, &token_response, &tokens);

    let usage = fetch_usage(config, &tokens)?;
    let evidence = save_evidence(config, "usage", &usage)?;
    println!("usage 响应已安全留存在 {}", evidence.body.display());
    println!("usage 响应头已安全留存在 {}", evidence.headers.display());

    // Claude 的套餐名不在 token 响应里（见 `docs/移动端额度展示要求.md` §8.1）。
    // profile 是目前唯一还没排除的来源，顺带采一份，失败不阻断 usage 基线。
    if config.slug == "claude" {
        match fetch_claude_profile(&tokens) {
            Ok(profile) => {
                let evidence = save_evidence(config, "profile", &profile)?;
                println!("profile 响应已安全留存在 {}", evidence.body.display());
                println!(
                    "profile HTTP {}；套餐名字段路径请在该文件里比对。",
                    profile.status
                );
            }
            Err(error) => println!("profile 采集未完成：{error}（不影响 usage 基线）"),
        }
    }

    if !usage.status.is_success() {
        return Err(format!(
            "usage 返回 HTTP {}；完整错误响应已留存在本地忽略目录，未输出到终端。",
            usage.status
        ));
    }

    if serde_json::from_str::<Value>(&usage.body).is_err() {
        return Err("usage 返回 2xx，但响应体不是 JSON；原始响应已安全留存。".to_owned());
    }

    println!(
        "Q4 {} 基线完成：token 交换与 usage 均返回成功。接下来先做字段路径比对和脱敏，再开始 scope 削减实验。",
        config.display_name
    );
    Ok(())
}

fn provider_config(provider: Provider) -> ProviderConfig {
    match provider {
        Provider::Codex => ProviderConfig {
            display_name: "Codex",
            slug: "codex",
            authorize_endpoint: "https://auth.openai.com/oauth/authorize",
            token_endpoint: "https://auth.openai.com/oauth/token",
            usage_endpoint: "https://chatgpt.com/backend-api/wham/usage",
            client_id: "app_EMoamEEZ73f0CkXaXp7hrann",
            scopes: "openid profile email offline_access api.connectors.read api.connectors.invoke",
            callback_path: "/auth/callback",
            ports: &[1455, 1457],
        },
        Provider::Claude => ProviderConfig {
            display_name: "Claude",
            slug: "claude",
            authorize_endpoint: "https://claude.com/cai/oauth/authorize",
            token_endpoint: "https://platform.claude.com/v1/oauth/token",
            usage_endpoint: "https://api.anthropic.com/api/oauth/usage",
            client_id: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
            scopes: "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload",
            callback_path: "/callback",
            ports: &[41999],
        },
    }
}

fn bind_loopback(config: ProviderConfig) -> Result<Loopback, String> {
    for port in config.ports {
        let address = format!("127.0.0.1:{port}");
        if let Ok(listener) = TcpListener::bind(&address) {
            listener
                .set_nonblocking(true)
                .map_err(|_| "无法将本地回调 server 设为非阻塞模式。".to_owned())?;
            return Ok(Loopback {
                listener,
                // redirect URI 必须使用 localhost 字面量，而不是 server 实际绑定的 127.0.0.1。
                redirect_uri: format!("http://localhost:{port}{}", config.callback_path),
            });
        }
    }

    Err(format!(
        "{} 的允许回调端口均不可用（{}）；请释放端口后重试。",
        config.display_name,
        config
            .ports
            .iter()
            .map(u16::to_string)
            .collect::<Vec<_>>()
            .join("、")
    ))
}

fn build_authorize_url(
    config: ProviderConfig,
    redirect_uri: &str,
    scope: &str,
    state: &str,
    verifier: &str,
) -> Result<Url, String> {
    let challenge = URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()));
    let mut url =
        Url::parse(config.authorize_endpoint).map_err(|_| "authorize 端点格式无效。".to_owned())?;
    {
        let mut query = url.query_pairs_mut();
        query
            .append_pair("response_type", "code")
            .append_pair("client_id", config.client_id)
            .append_pair("redirect_uri", redirect_uri)
            .append_pair("scope", scope)
            .append_pair("code_challenge_method", "S256")
            .append_pair("code_challenge", &challenge)
            .append_pair("state", state);

        match config.slug {
            "codex" => {
                query
                    .append_pair("id_token_add_organizations", "true")
                    .append_pair("codex_cli_simplified_flow", "true")
                    .append_pair("originator", "codex_cli_rs");
            }
            "claude" => {
                query.append_pair("code", "true");
            }
            _ => unreachable!("only the two documented providers exist"),
        }
    }
    Ok(url)
}

fn wait_for_callback(
    listener: &TcpListener,
    expected_state: &str,
    timeout: Duration,
) -> Result<Callback, String> {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        match listener.accept() {
            Ok((mut stream, _)) => {
                if let Some(callback) = handle_callback(&mut stream, expected_state)? {
                    return Ok(callback);
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(100));
            }
            Err(_) => return Err("本地回调 server 接受连接失败。".to_owned()),
        }
    }
    Err("等待浏览器回调超时；未发送 token 或 usage 请求。".to_owned())
}

fn handle_callback(
    stream: &mut TcpStream,
    expected_state: &str,
) -> Result<Option<Callback>, String> {
    let mut request = [0_u8; 8 * 1024];
    let bytes = stream
        .read(&mut request)
        .map_err(|_| "无法读取本地回调请求。".to_owned())?;
    let request = std::str::from_utf8(&request[..bytes])
        .map_err(|_| "本地回调请求不是有效 UTF-8。".to_owned())?;
    let Some(target) = request
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
    else {
        reply(
            stream,
            "400 Bad Request",
            "无效回调",
            "回调格式无效，请回到终端重试。",
        )?;
        return Ok(None);
    };

    let callback = Url::parse(&format!("http://localhost{target}"))
        .map_err(|_| "本地回调 URL 无效。".to_owned())?;
    let parameters = callback.query_pairs().collect::<BTreeMap<_, _>>();

    if parameters.contains_key("error") {
        reply(
            stream,
            "400 Bad Request",
            "授权未完成",
            "授权被取消或被 Provider 拒绝；请回到终端查看非敏感状态。",
        )?;
        return Err("Provider 未返回 authorization code；未发送 token 或 usage 请求。".to_owned());
    }

    let Some(state) = parameters.get("state") else {
        reply(
            stream,
            "400 Bad Request",
            "无效回调",
            "回调缺少 state，请回到终端重试。",
        )?;
        return Ok(None);
    };
    if state != expected_state {
        reply(
            stream,
            "400 Bad Request",
            "无效回调",
            "回调 state 不匹配，请回到终端重试。",
        )?;
        return Ok(None);
    }
    let Some(code) = parameters.get("code").filter(|code| !code.is_empty()) else {
        reply(
            stream,
            "400 Bad Request",
            "无效回调",
            "回调缺少 code，请回到终端重试。",
        )?;
        return Ok(None);
    };

    reply(stream, "200 OK", "授权已接收", "可以关闭此页面并回到终端。")?;
    Ok(Some(Callback {
        code: code.to_string(),
    }))
}

fn reply(stream: &mut TcpStream, status: &str, title: &str, body: &str) -> Result<(), String> {
    let page =
        format!("<!doctype html><meta charset=\"utf-8\"><title>{title}</title><p>{body}</p>");
    let response = format!(
        "HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{page}",
        page.len()
    );
    stream
        .write_all(response.as_bytes())
        .map_err(|_| "无法响应本地回调浏览器页面。".to_owned())
}

fn exchange_code(
    config: ProviderConfig,
    redirect_uri: &str,
    verifier: &str,
    state: &str,
    code: &str,
) -> Result<Value, String> {
    let client = http_client()?;
    let response = match config.slug {
        "codex" => client
            .post(config.token_endpoint)
            .header(ACCEPT, "application/json")
            .form(&[
                ("grant_type", "authorization_code"),
                ("code", code),
                ("redirect_uri", redirect_uri),
                ("client_id", config.client_id),
                ("code_verifier", verifier),
            ])
            .send(),
        "claude" => client
            .post(config.token_endpoint)
            .header(ACCEPT, "application/json")
            .json(&json!({
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirect_uri,
                "client_id": config.client_id,
                "code_verifier": verifier,
                "state": state,
            }))
            .send(),
        _ => unreachable!("only the two documented providers exist"),
    }
    .map_err(|_| "token 请求未能完成；未输出或落盘响应内容。".to_owned())?;

    let status = response.status();
    let body = response
        .text()
        .map_err(|_| "无法读取 token 响应；未输出或落盘响应内容。".to_owned())?;
    let value = serde_json::from_str::<Value>(&body)
        .map_err(|_| "token 响应不是 JSON；未输出或落盘响应内容。".to_owned())?;
    if !status.is_success() {
        return Err(format!(
            "token 交换返回 HTTP {status}；响应字段结构会显示在终端，所有值均已丢弃。{}",
            token_schema(&value)
        ));
    }
    Ok(value)
}

fn parse_tokens(config: ProviderConfig, response: &Value) -> Result<TokenSet, String> {
    let access_token = response
        .get("access_token")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| "token 交换成功但缺少 access_token；不会继续请求 usage。".to_owned())?
        .to_owned();
    if response
        .get("refresh_token")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .is_none()
    {
        return Err(
            "token 交换成功但缺少 refresh_token；Q4 检查项未通过，不会继续请求 usage。".to_owned(),
        );
    }
    let id_token = response
        .get("id_token")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(str::to_owned);

    let (account_id, account_id_source) = if matches!(config.slug, "codex") {
        find_account_id(&access_token, id_token.as_deref())
    } else {
        (None, None)
    };

    Ok(TokenSet {
        access_token,
        id_token,
        account_id,
        account_id_source,
    })
}

fn find_account_id(
    access_token: &str,
    id_token: Option<&str>,
) -> (Option<String>, Option<&'static str>) {
    if let Some(value) = jwt_claim(access_token, "chatgpt_account_id") {
        return (Some(value), Some("access_token claim"));
    }
    if let Some(value) = id_token.and_then(|token| jwt_claim(token, "chatgpt_account_id")) {
        return (Some(value), Some("id_token claim"));
    }
    (None, None)
}

fn fetch_usage(config: ProviderConfig, tokens: &TokenSet) -> Result<UsageResponse, String> {
    let client = http_client()?;
    let mut request = client
        .get(config.usage_endpoint)
        .header(AUTHORIZATION, format!("Bearer {}", tokens.access_token))
        .header(ACCEPT, "application/json");

    match config.slug {
        "codex" => {
            request = request.header(USER_AGENT, "codex-cli");
            if let Some(account_id) = &tokens.account_id {
                request = request.header("ChatGPT-Account-Id", account_id);
            }
        }
        "claude" => {
            request = request.header("anthropic-beta", "oauth-2025-04-20");
        }
        _ => unreachable!("only the two documented providers exist"),
    }

    let response = request
        .send()
        .map_err(|_| "usage 请求未能完成；未输出 token 或响应内容。".to_owned())?;
    let status = response.status();
    let headers = response.headers().clone();
    let body = response
        .text()
        .map_err(|_| "无法读取 usage 响应；未输出 token 或响应内容。".to_owned())?;
    Ok(UsageResponse {
        status,
        headers,
        body,
    })
}

/// Claude Code 官方客户端登录后会请求它；这里只读，不写回任何东西。
fn fetch_claude_profile(tokens: &TokenSet) -> Result<UsageResponse, String> {
    let client = http_client()?;
    let response = client
        .get("https://api.anthropic.com/api/oauth/profile")
        .header(AUTHORIZATION, format!("Bearer {}", tokens.access_token))
        .header(ACCEPT, "application/json")
        .send()
        .map_err(|_| "profile 请求未能完成；未输出 token 或响应内容。".to_owned())?;
    let status = response.status();
    let headers = response.headers().clone();
    let body = response
        .text()
        .map_err(|_| "无法读取 profile 响应；未输出 token 或响应内容。".to_owned())?;
    Ok(UsageResponse {
        status,
        headers,
        body,
    })
}

struct EvidencePaths {
    body: PathBuf,
    headers: PathBuf,
}

fn save_evidence(
    config: ProviderConfig,
    label: &str,
    response: &UsageResponse,
) -> Result<EvidencePaths, String> {
    let raw_dir = repository_root().join("fixtures/raw");
    fs::create_dir_all(&raw_dir).map_err(|_| "无法创建本地证据目录 fixtures/raw。".to_owned())?;
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| "系统时间早于 Unix epoch，无法为证据文件命名。".to_owned())?
        .as_millis();
    let body = raw_dir.join(format!("{}-{label}-{timestamp}.json", config.slug));
    let headers = raw_dir.join(format!("{}-{label}-{timestamp}.headers.txt", config.slug));

    write_owner_only(&body, &response.body)?;
    write_owner_only(&headers, &safe_headers(response.status, &response.headers))?;
    Ok(EvidencePaths { body, headers })
}

fn safe_headers(status: StatusCode, headers: &HeaderMap) -> String {
    let mut result = format!("HTTP {status}\n");
    for (name, value) in headers {
        if name.as_str().eq_ignore_ascii_case("set-cookie") {
            continue;
        }
        if let Ok(value) = value.to_str() {
            result.push_str(name.as_str());
            result.push_str(": ");
            result.push_str(value);
            result.push('\n');
        }
    }
    result
}

fn write_owner_only(path: &Path, contents: &str) -> Result<(), String> {
    let mut file = open_owner_only(path)?;
    file.write_all(contents.as_bytes())
        .map_err(|_| "无法写入本地证据文件。".to_owned())
}

#[cfg(unix)]
fn open_owner_only(path: &Path) -> Result<File, String> {
    use std::{
        fs::Permissions,
        os::unix::fs::{OpenOptionsExt, PermissionsExt},
    };

    let file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)
        .map_err(|_| "无法创建本地证据文件。".to_owned())?;
    fs::set_permissions(path, Permissions::from_mode(0o600))
        .map_err(|_| "无法设置本地证据文件权限。".to_owned())?;
    Ok(file)
}

#[cfg(not(unix))]
fn open_owner_only(path: &Path) -> Result<File, String> {
    OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|_| "无法创建本地证据文件。".to_owned())
}

fn print_token_evidence(config: ProviderConfig, response: &Value, tokens: &TokenSet) {
    println!("token 响应结构：{}", token_schema(response));
    println!(
        "access_token exp：{}",
        jwt_exp(&tokens.access_token)
            .map(|value| value.to_string())
            .unwrap_or_else(|| "absent".to_owned())
    );
    if let Some(id_token) = &tokens.id_token {
        println!(
            "id_token exp：{}",
            jwt_exp(id_token)
                .map(|value| value.to_string())
                .unwrap_or_else(|| "absent".to_owned())
        );
    }
    if matches!(config.slug, "codex") {
        let status = tokens
            .account_id_source
            .map(|source| format!("present ({source})"))
            .unwrap_or_else(|| "absent".to_owned());
        println!("account_id: {status}");
    }
}

fn token_schema(value: &Value) -> String {
    let Some(object) = value.as_object() else {
        return "non-object JSON".to_owned();
    };
    let mut fields = object
        .iter()
        .map(|(name, value)| {
            let shape = match value {
                Value::String(value) => format!("string(length={})", value.len()),
                Value::Number(_) => "number".to_owned(),
                Value::Bool(_) => "boolean".to_owned(),
                Value::Null => "null".to_owned(),
                Value::Array(values) => format!("array(length={})", values.len()),
                Value::Object(values) => format!("object(keys={})", values.len()),
            };
            format!("{name}: {shape}")
        })
        .collect::<Vec<_>>();
    fields.sort();
    fields.join(", ")
}

fn jwt_claim(token: &str, claim: &str) -> Option<String> {
    let payload = jwt_payload(token)?;
    payload
        .get(OPENAI_AUTH_CLAIM_NAMESPACE)
        .and_then(|namespace| namespace.get(claim))
        .or_else(|| payload.get(claim))
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
}

fn jwt_exp(token: &str) -> Option<i64> {
    jwt_payload(token)?.get("exp")?.as_i64()
}

fn jwt_payload(token: &str) -> Option<Value> {
    let mut segments = token.split('.');
    let _header = segments.next()?;
    let payload = segments.next()?;
    segments.next()?;
    if segments.next().is_some() {
        return None;
    }
    let bytes = URL_SAFE_NO_PAD
        .decode(payload)
        .or_else(|_| URL_SAFE.decode(payload))
        .ok()?;
    serde_json::from_slice(&bytes).ok()
}

fn random_base64url(bytes: usize) -> String {
    let mut value = vec![0_u8; bytes];
    OsRng.fill_bytes(&mut value);
    URL_SAFE_NO_PAD.encode(value)
}

fn http_client() -> Result<Client, String> {
    Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|_| "无法创建 HTTP client。".to_owned())
}

fn repository_root() -> &'static Path {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(2)
        .expect("verify/oauth must be two levels below the repository root")
}

#[cfg(test)]
mod tests {
    use super::*;

    const JWT_WITH_ACCOUNT: &str = concat!(
        "eyJhbGciOiJub25lIn0.",
        "eyJodHRwczovL2FwaS5vcGVuYWkuY29tL2F1dGgiOnsiY2hhdGdwdF9hY2NvdW50X2lkIjoiYWNjdF90ZXN0In0sImV4cCI6MTcwMDAwMDAwMH0.",
        "signature"
    );

    #[test]
    fn codex_authorize_url_keeps_the_documented_fixed_callback() {
        let config = provider_config(Provider::Codex);
        let url = build_authorize_url(
            config,
            "http://localhost:1455/auth/callback",
            config.scopes,
            "state",
            "verifier",
        )
        .expect("documented URL is valid");
        let query = url.query_pairs().collect::<BTreeMap<_, _>>();

        assert_eq!(
            query.get("redirect_uri"),
            Some(&"http://localhost:1455/auth/callback".into())
        );
        assert_eq!(query.get("code_challenge_method"), Some(&"S256".into()));
        assert_eq!(
            query.get("id_token_add_organizations"),
            Some(&"true".into())
        );
    }

    #[test]
    fn claude_authorize_url_contains_its_non_standard_code_parameter() {
        let config = provider_config(Provider::Claude);
        let url = build_authorize_url(
            config,
            "http://localhost:41999/callback",
            config.scopes,
            "state",
            "verifier",
        )
        .expect("documented URL is valid");
        let query = url.query_pairs().collect::<BTreeMap<_, _>>();

        assert_eq!(query.get("code"), Some(&"true".into()));
        assert_eq!(
            query.get("redirect_uri"),
            Some(&"http://localhost:41999/callback".into())
        );
    }

    #[test]
    fn account_id_is_read_from_the_namespaced_claim_without_exposing_its_value() {
        let (account_id, source) = find_account_id(JWT_WITH_ACCOUNT, None);

        assert_eq!(account_id.as_deref(), Some("acct_test"));
        assert_eq!(source, Some("access_token claim"));
    }

    #[test]
    fn token_schema_contains_lengths_but_not_token_values() {
        let response = json!({"access_token": "secret-value", "expires_in": 3600});
        let summary = token_schema(&response);

        assert!(summary.contains("access_token: string(length=12)"));
        assert!(summary.contains("expires_in: number"));
        assert!(!summary.contains("secret-value"));
    }

    #[test]
    fn evidence_headers_never_keep_set_cookie() {
        let mut headers = HeaderMap::new();
        headers.insert(
            "set-cookie",
            "session=secret".parse().expect("valid header"),
        );
        headers.insert("retry-after", "60".parse().expect("valid header"));

        let result = safe_headers(StatusCode::TOO_MANY_REQUESTS, &headers);
        assert!(result.contains("retry-after: 60"));
        assert!(!result.contains("session=secret"));
    }
}

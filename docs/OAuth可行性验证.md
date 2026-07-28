# OAuth 可行性验证

> 状态：**Q1、Q2 已通过（2026-07-28，macOS 命令行 + 浏览器）；Q3、Q4 未开始**
> 这是启动 CC Trace Mobile 之前必须先完成的事。结论出来之前不写界面。

## 为什么这件事排在最前面

桌面端的凭据是白捡的：直接读本机 `~/.codex`、`~/.claude`，零登录成本，所以桌面端**从来没有走过完整的 OAuth 授权流程**——它只用已有的 `refresh_token` 换新 token。

移动端读不到任何本机凭据，必须自己从零走完整的授权码流程。这是移动端相对桌面端**唯一真正新增、且完全没有验证过**的部分，工作量大概率超过所有界面加起来。

更关键的是：它可能根本走不通。走不通的话，界面做得再好也没有数据。

## 已知事实

以下来自桌面端 `src-tauri/src/providers/`，已于 2026-07-27 在 macOS 完成真实数据验证：

| | Codex | Claude Code |
|---|---|---|
| 额度接口 | `https://chatgpt.com/backend-api/wham/usage` | `https://api.anthropic.com/api/oauth/usage` |
| Token 接口 | `https://auth.openai.com/oauth/token` | `https://platform.claude.com/v1/oauth/token` |
| client_id | `app_EMoamEEZ73f0CkXaXp7hrann` | `9d1c250a-e61b-44d9-88ed-5944d1962f5e` |

这两个 `client_id` 属于 Codex CLI 和 Claude Code 官方客户端，是公开值。Claude 的
`9d1c250a-…` 已于 2026-07-28 在本机 Claude Code 2.1.206 二进制的 prod 配置里复核，一致。

**桌面端已验证的只有 token 刷新和 usage 查询这两步。** authorize 端点、PKCE 参数、
redirect_uri 白名单原本全部未知，2026-07-28 由 Q1 / Q2 补齐，见下。

## 待验证问题

按「能否否决整个项目」排序。

### Q1 · redirect_uri 白名单允许什么？（决定性）

这是唯一一个答错就要推翻 [ADR-0001](决策/ADR-0001-独立仓库与技术栈选型.md) 的问题。

Nowdex 安装包里观察到的回调是 loopback：

```text
Codex:  http://localhost:1455/auth/callback
Claude: http://localhost:54545/callback
```

如果白名单只有这两个 loopback 地址，**这未必是坏消息**——手机上的 `localhost` 就是手机自己。应用内起一个监听对应端口的本地 HTTP server，用系统浏览器打开 authorize URL，重定向回 `localhost:1455` 时能被自己接住。Android 上这是 AppAuth 早年的标准做法，iOS 上同样可行。

> 我此前判断「Provider 未必把移动端 redirect URI 列进白名单」是个可行性风险。补充 loopback 这条路径后，风险比那个判断要低——但仍需实测确认。

真正的坏情况是白名单要求了移动端拿不到的东西（例如绑定到桌面应用签名的自定义 scheme）。

**判定**：能拿到 authorization code 即通过。

#### 结论：**通过**（2026-07-28，macOS，用户本人账号真实登录）

两个 Provider 都成功收到 authorization code，state 校验通过。code 未换 token、未落盘。
**不触发 [ADR-0001](决策/ADR-0001-独立仓库与技术栈选型.md) 复审条件。**

两家的白名单宽严差别很大：

| redirect_uri | Codex | Claude |
|---|---|---|
| `http://localhost:1455/auth/callback` | ✅ 拿到 code | — |
| `http://localhost:1457/auth/callback` | ✅ 到达登录页 | — |
| `http://localhost:41999/callback` | — | ✅ 拿到 code |
| 任意其他端口 | ❌ 拒绝 | ✅ 接受 |
| `http://127.0.0.1:<port>/…`（IP 字面量） | ❌ 拒绝 | ❌ 拒绝 |
| 自定义 scheme `cctrace://…` | ❌ 拒绝 | ❌ 拒绝 |
| 相同端口但换路径 | ❌ 拒绝 | > 未验证 |

**Codex 是精确白名单。** 只认 `http://localhost:1455/auth/callback` 和
`http://localhost:1457/auth/callback` 两个字面量——后者在 Codex 源码里被注释为
"the registered fallback port"，印证了这是服务端注册的固定列表。被拒时表现为跳转
`auth.openai.com/error?payload=…`，`errorCode` 为 `unknown_error`（不是标准 OAuth
错误码，无法从错误本身区分「redirect 不合法」和其他失败）。

**Claude 接受任意 localhost 端口，但主机名必须是 `localhost` 字面量。** 实测 41999
直接通过；`127.0.0.1:41999` 被拒。这与 Claude Code 自身实现一致：它的回调 server 用
`listen(0, "127.0.0.1")`（绑定用 IP，但 redirect_uri 里写 `localhost`），端口由系统
临时分配，因此服务端白名单必然对 localhost 端口开放。从「任意端口通过、IP 字面量被拒」
推断，Anthropic 注册的应是 `http://localhost:*/callback` 这类模式，而非逐条枚举。

Claude 被拒时的报错比 Codex 有用得多，是明确的英文说明：

```text
Authorization failed
Redirect URI cctrace://callback is not supported by client.
```

「not supported by **client**」指向的是 client_id 的注册项，不是请求格式问题。

**两家都不接受自定义 scheme。** 这一条是 2026-07-28 实测的，不是推断——原本期望
Claude 可能接受原生 scheme（那样移动端就不必起本地 HTTP server），已被否定。
**移动端两个 Provider 都只能走 loopback。**

**端点补记**：`https://claude.com/cai/oauth/authorize` 只是跳板，最终 302 到
`https://claude.ai/oauth/authorize`。移动端直接用后者可以少一跳。

#### 由此产生的移动端硬约束

1. **Codex 必须抢占 1455，失败时退 1457，再失败就无法登录。** 只有两个备选，没有第三个。
   移动端上端口冲突概率低但非零（尤其 Android 上其他 App 也可能监听），要有明确的
   失败文案，不能静默卡住。
2. **authorize 页必须用真实浏览器打开。** `auth.openai.com/oauth/authorize` 有
   Cloudflare 人机校验（响应头 `Cf-Mitigated: challenge`），普通 HTTP 客户端直接 403。
   iOS 用 `ASWebAuthenticationSession`、Android 用 Custom Tabs 都满足；**自己 fetch 或
   塞进裸 WebView 会被拦**。
3. **Claude 的 redirect_uri 校验发生在登录之后。** 未登录时 `claude.com/cai/oauth/authorize`
   只跳 `claude.ai/login?returnTo=…`，不校验参数。意味着参数错了要等用户登录完才暴露，
   错误提示时机比 Codex 晚。
4. **两家都必须用 `localhost` 字面量，不能用 `127.0.0.1`。** 本地 server 绑定用
   `127.0.0.1` 没问题（Claude Code 就是这么做的），但拼进 redirect_uri 的必须是
   `localhost`。
5. **自定义 scheme 两家都不接受，loopback 是唯一路径。** 这直接决定 Q3 无法绕开
   「在手机上跑一个本地 HTTP server」这件事。

### Q2 · authorize 端点和 PKCE 参数是什么？

需要确认 authorize URL、必需的 query 参数、PKCE 的 `code_challenge_method`（预期 `S256`）、以及 `scope` 的最小可用集合。

10 号参考文档里观察到过一组 Claude scope（`user:profile`、`user:inference`、`user:sessions:claude_code` 等），但那是静态字符串。**按 usage 接口实际需要申请最小 scope，不照抄。**

**判定**：能构造出被接受的 authorize 请求即通过。

#### 结论：**通过**（2026-07-28，macOS）

两个 Provider 的 authorize 请求都被接受并走完到 code 返回。参数不是猜的，来源如下：

- **Codex**：[openai/codex](https://github.com/openai/codex) 开源仓库
  `codex-rs/login/src/server.rs` 的 `build_authorize_url()`，与本机 codex 0.145.0
  二进制中的字符串一致
- **Claude**：本机 Claude Code 2.1.206 二进制中的 `buildAuthUrl()`（该版本为 Bun 打包的
  单文件可执行，JS 源码可直接提取）

##### Codex

authorize 端点 `https://auth.openai.com/oauth/authorize`：

| 参数 | 值 |
|---|---|
| `response_type` | `code` |
| `client_id` | `app_EMoamEEZ73f0CkXaXp7hrann` |
| `redirect_uri` | `http://localhost:1455/auth/callback` |
| `scope` | `openid profile email offline_access api.connectors.read api.connectors.invoke` |
| `code_challenge_method` | `S256` |
| `code_challenge` | PKCE，`base64url(sha256(verifier))` 去 padding |
| `state` | 32 字节随机，base64url 去 padding |
| `id_token_add_organizations` | `true` |
| `codex_cli_simplified_flow` | `true` |
| `originator` | `codex_cli_rs` |

回调返回 `code`、`state`、`scope` 三个参数。token 交换为
`POST https://auth.openai.com/oauth/token`，`Content-Type: application/x-www-form-urlencoded`，
body 为 `grant_type=authorization_code&code=…&redirect_uri=…&client_id=…&code_verifier=…`。

##### Claude

有两个 authorize 端点，按账号类型分：

- `https://claude.com/cai/oauth/authorize` —— claude.ai 订阅账号（**移动端要用这个**）
- `https://platform.claude.com/oauth/authorize` —— Console / API 账号

| 参数 | 值 |
|---|---|
| `code` | `true`（非标准，Claude Code 固定带） |
| `client_id` | `9d1c250a-e61b-44d9-88ed-5944d1962f5e` |
| `response_type` | `code` |
| `redirect_uri` | `http://localhost:<任意端口>/callback` |
| `scope` | 见下 |
| `code_challenge_method` | `S256` |
| `code_challenge` | 同 Codex |
| `state` | 同 Codex |
| `orgUUID` / `login_hint` / `login_method` | 可选，移动端不需要 |

回调只返回 `code` 和 `state`。token 交换为
`POST https://platform.claude.com/v1/oauth/token`，**`Content-Type: application/json`**
（与 Codex 的 form-urlencoded 不同，别混），body 为
`{grant_type, code, redirect_uri, client_id, code_verifier, state}`——注意 `state`
也要放进 token 请求，这不是标准 OAuth 行为，但 Claude Code 是这么发的。

Claude Code 完整 scope 集合：

```text
org:create_api_key user:profile user:inference
user:sessions:claude_code user:mcp_servers user:file_upload
```

其中 Claude Code 自身有个 `inferenceOnly` 模式，只申请 `user:inference` 一项——说明
服务端接受 scope 子集，不强制全量。

##### 最小 scope

> 待确认。usage 接口 `https://api.anthropic.com/api/oauth/usage` 实际需要哪些 scope，
> 要到 Q4 拿 token 实调才知道。目前只知道全量集合可用，以及服务端接受子集。
>
> 假设错误的影响：如果申请的 scope 少于所需，Q4 会拿到 403 而不是额度数据，需要回到
> Q2 补 scope 重走一次授权；不影响 Q1 的白名单结论。

**这里有个跟「只读额度」原则冲突的事实要记录**：两家都没有只读额度的 scope。Codex 的
`api.connectors.invoke` 和 Claude 的 `user:inference` 都能直接消耗账号额度调模型。
也就是说，为了读余量而签发的 token，权限必然大于用途。这是协议层面的既定事实，
无法通过缩小 scope 规避（`user:inference` 是否可以从 Claude 的申请里去掉，待 Q4 确认）。

### Q3 · 本地 loopback server 在两个平台上都能接住回调吗？

- iOS：`ASWebAuthenticationSession` 打开授权页；应用在前台时本地 server 能否稳定监听
- Android：Chrome Custom Tabs；后台省电策略是否会掐掉监听
- 端口被占用、用户中途取消、重复回调、超时

Q1 已经把这一步的约束收窄了：**Codex 只能用 1455 / 1457 两个端口**，端口被占用不再是
边缘情况而是会直接堵死登录；Claude 可用任意端口，压力小得多。详见 Q1 的「由此产生的
移动端硬约束」。

**判定**：两个平台各成功 3 次、并各覆盖一次取消场景即通过。

### Q4 · 换到的 token 能否调通 usage 接口？

授权码换 token 之后，用它请求 usage，看返回的 JSON 结构是否和桌面端 fixture 一致。

不一致不算失败，但要记录差异——可能意味着移动端拿到的 scope 和桌面端不同。

**判定**：两个 Provider 都能返回可解析的额度数据即通过。

## 验证方式

先用**最小脚本**验证，不要在 Tauri 工程里做。Q1 和 Q2 完全可以在桌面命令行上跑通（loopback 在哪都一样），确认协议层可行之后，Q3 才需要真机。

顺序：Q2 → Q1 → Q4 → Q3。前三个在电脑上做，只有 Q3 必须上真机。

## 纪律

以下几条在验证阶段就要守住，不能等到写正式代码：

- access token、refresh token、authorization code 一律不进日志、不进剪贴板、不进 URL 之外的任何地方
- 真实响应存为**脱敏** fixture；原始响应不入库（`.gitignore` 已排除 `fixtures/raw/`）
- 用自己的账号验证，不使用他人凭据
- 只读额度，不碰对话内容

## 结论

> **Q1、Q2 通过（2026-07-28，macOS）；Q3、Q4 未开始。**
> 四个问题全部通过之前，不开始界面实现。

协议层已经跑通：两个 Provider 都能用官方 CLI 的 client_id 构造出被接受的 authorize
请求，并通过 loopback 回调拿到 authorization code。**移动端登录不存在协议层面的
不可行**，ADR-0001 不需要复审。

剩下的风险从「能不能做」变成了「稳不稳、能撑多久」：

| 风险 | 性质 | 归属 |
|---|---|---|
| Codex 只有 1455 / 1457 两个端口可用 | 实现约束，需要明确失败路径 | Q3 |
| 自定义 scheme 两家均不接受，必须在手机上跑本地 server | 实现约束，无绕开路径 | Q3 |
| authorize 页有 Cloudflare 校验，必须真实浏览器 | 实现约束，选型已满足 | Q3 |
| token 权限（`user:inference` / `api.connectors.invoke`）大于用途 | 协议既定，无法规避 | 记录，Q4 复核 |
| 冒用官方 CLI client_id，两家均无第三方接入渠道 | 产品风险，对方随时可收紧 | 见下 |

最后一条不是安全漏洞——凭据全程只输在 Provider 自己的登录页上，App 看不到。但它意味着
整个方案建立在「服务端不校验调用方是否真的是官方 CLI」这一前提上。对方加一道 UA 校验、
收紧 redirect_uri、或轮换 client_id，功能就会整体失效。这是继承自「仿照 Nowdex」这条
路径本身的代价，不是本项目引入的。

### 验证记录

| 项 | 日期 | 平台 | 方式 |
|---|---|---|---|
| Q2 参数来源 | 2026-07-28 | macOS | Codex 开源源码 + Claude Code 2.1.206 二进制提取 |
| Q1 白名单矩阵 | 2026-07-28 | macOS | 浏览器逐个探测 authorize 端点 |
| Q1 拿到 code | 2026-07-28 | macOS | 本机 loopback server + 用户本人账号真实登录 |
| Q1 补测（scheme / IP 字面量） | 2026-07-28 | macOS | 同上，两项 Claude 侧均被拒 |
| Q3 | — | iOS / Android 均未验证 | — |
| Q4 | — | 未验证 | — |

验证过程中 authorization code 未被解析、未落盘、未换取 token；未读写本机
`~/.codex` 与 `~/.claude` 的任何凭据。

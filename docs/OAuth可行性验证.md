# OAuth 可行性验证

> 状态：**Q1、Q2 与 Q4 基线已通过（2026-07-28，macOS 命令行 + 浏览器）；Q3 静态实现
> 已通过 Android 编译，iOS Runner 源码已通过独立 Swift 类型检查，但尚未真机验证；Q4 的
> scope / 限流 / `is_active` 补充实验进行中。**
> 原定“结论出来前不写界面”的开发顺序已由用户于 2026-07-29 明确调整，验收门槛不变。

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
`9d1c250a-…` 已于 2026-07-28 在 Claude Code 2.1.206 二进制的 prod 配置里复核，一致。

**桌面端已验证的只有 token 刷新和 usage 查询这两步。** authorize 端点、PKCE 参数、
redirect_uri 白名单原本全部未知，2026-07-28 由 Q1 / Q2 补齐，见下。

## 待验证问题

按「能否否决整个项目」排序。

### Q1 · redirect_uri 白名单允许什么？（决定性）

这是唯一一个答错就会否决当前移动端产品形态，并触发
[ADR-0002](决策/ADR-0002-Flutter移动端技术栈.md) 复审的问题。

Nowdex 安装包里观察到的回调是 loopback：

```text
Codex:  http://localhost:1455/auth/callback
Claude: http://localhost:54545/callback
```

如果白名单只有这两个 loopback 地址，**这未必是坏消息**——手机上的 `localhost` 就是手机自己。应用内起一个监听对应端口的本地 HTTP server，用系统浏览器打开 authorize URL，重定向回 `localhost:1455` 时能被自己接住。Android 上这是 AppAuth 早年的标准做法，iOS 上同样可行。

> 此前将「Provider 未必把移动端 redirect URI 列进白名单」视为可行性风险。补充 loopback
> 路径后，这项风险降低，但仍需实测确认。

真正的坏情况是白名单要求了移动端拿不到的东西（例如绑定到桌面应用签名的自定义 scheme）。

**判定**：能拿到 authorization code 即通过。

#### 结论：**通过**（2026-07-28，macOS，账号持有人真实登录）

两个 Provider 都成功收到 authorization code，state 校验通过。code 未换 token、未落盘。
**不触发当前产品形态或 [ADR-0002](决策/ADR-0002-Flutter移动端技术栈.md) 的复审。**

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
  `codex-rs/login/src/server.rs` 的 `build_authorize_url()`，与 codex 0.145.0
  二进制中的字符串一致
- **Claude**：Claude Code 2.1.206 二进制中的 `buildAuthUrl()`（该版本为 Bun 打包的
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

Q3 在 [实施计划的 S1 验证框架](实施计划.md) 内执行：必须是 Flutter 应用在真机上的
真实浏览器与本地 server 链路，macOS 命令行脚本不能替代。因用户明确调整开发顺序，
正式额度 UI、Token 持久化与 usage 请求现已静态实现；它们不属于 Q3 证据。原最小 Q3
工具保留在 Debug 构建的设置页，尚未真机运行。

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

**判定**：两个 Provider 都能返回可解析的额度数据即通过。详细检查表见 4.6。

以下 4.1–4.7 是可直接执行的方案，不需要再做设计判断。

#### 4.1 Q4 必须把 Q1 重跑一遍

Q1 拿到的 authorization code **不能复用**：它是一次性的，且当时明确未换 token、未落盘，早已失效。

因此 Q4 是一条端到端链路，不是接着 Q1 的接力棒：

```text
起 loopback server → 系统浏览器打开 authorize → 接住 code
  → ① 换 token → ② 调 usage → ③ 落盘脱敏 fixture
```

Q1、Q2 的脚本没有入库，这次要重写。**本次脚本必须入库**——Q3 上真机时还要再走一遍同样的流程。

#### 4.2 三个未知数

文档原本只写了 scope 一个，实际有三个，其中第三个是移动端独有的。

**① scope 是否够。** 见 Q2「最小 scope」小节，目前只知道全量集合可用、服务端接受子集。

**② Claude 的跨域名组合是否成立。** authorize 在 `claude.ai/oauth/authorize`，token 交换在 `platform.claude.com/v1/oauth/token`。Q1 只验到 code 为止，这个跨域名组合从未实测。

**③ Codex 的 `ChatGPT-Account-Id` 从哪来。**（桌面端无法回答的新问题）

桌面端调 usage 时带了这个头，来源是三级回退，见 cc-trace 的 `src-tauri/src/providers/credentials/codex.rs`：

```text
tokens.account_id（auth.json 字段）
  → access_token 的 chatgpt_account_id claim
  → id_token 的 chatgpt_account_id claim
```

**第一级在移动端根本不存在**（没有 auth.json），只能靠后两级从 JWT payload 里解。桌面端一直走的是第一级，所以它验证过的事实在这里用不上。

Q2 记录的 authorize 参数里有 `id_token_add_organizations=true`，**推测**正是为了让 id_token 携带 org / account 信息——但这是推断，Q4 要实测。

> 风险：三级全空时，Codex 的 usage 失败表现**与 scope 不足完全一样**（都是 4xx）。
> 因此脚本必须在换到 token 的当下就输出 `account_id: present / absent`（只输出有无，不输出值），
> 否则两种原因无法区分。

#### 4.3 脚本形态

| 项 | 规定 | 理由 |
|---|---|---|
| 语言 | Rust，独立 bin crate | 作为已验证、可复核的协议证据工具；未来 Flutter 应用用 Dart 独立实现 |
| 位置 | `verify/oauth/`，入库 | 与未来 Flutter 应用隔离，不复用为应用代码 |
| 结构 | 一个 crate，两个 bin：`q4-codex`、`q4-claude` | 两家的 body 格式、请求头、端口差异过多，合并只会全是分支 |
| 职责 | **只做网络请求与落盘，不做归一化** | 搬桌面端 normalize 会拖进 contracts 整套依赖，与验证目的无关 |

**执行者不得做的事**：不要执行 `tauri init` 或任何平台初始化；不要写界面；不要实现 Provider trait、状态机或存储；不要把 token 写进任何文件（含 `fixtures/raw/`，理由见「证据留存」B 档）。

##### 请求事实

以下来自 cc-trace `src-tauri/src/providers/` 的已验证实现（2026-07-27 macOS 真实数据），**证据等级高，照抄即可**：

| | Codex | Claude |
|---|---|---|
| usage 端点 | `GET https://chatgpt.com/backend-api/wham/usage` | `GET https://api.anthropic.com/api/oauth/usage` |
| `Authorization` | `Bearer <access_token>` | 同左 |
| `Accept` | `application/json` | `application/json` |
| 专有头 | `User-Agent: codex-cli`<br>`ChatGPT-Account-Id: <account_id>` | `anthropic-beta: oauth-2025-04-20` |
| token 端点 | `POST https://auth.openai.com/oauth/token` | `POST https://platform.claude.com/v1/oauth/token` |
| token 请求体 | `application/x-www-form-urlencoded` | **`application/json`** |
| 请求体额外字段 | — | **必须带 `state`**（非标准，Claude Code 如此发送） |

> usage 端点没有 Cloudflare 人机校验——桌面端用普通 HTTP 客户端已跑通。
> 有校验的只是 authorize **页面**，见 Q1 硬约束第 2 条。

##### 端口

Codex 固定用 `1455`（占用时退 `1457`，仅此两个）；Claude 固定用 `41999`（Q1 已验证通过），减少变量。两者的 `redirect_uri` 都必须用 `localhost` 字面量，且 token 交换时要与 authorize 时**完全一致**。

#### 4.4 执行顺序：先全量 scope，再削减

**必须先用 Q2 记录的全量 scope 跑通，再做削减实验。不要反过来。**

反过来的问题是变量没有隔离：先试最小 scope 时拿到 4xx，无法区分是 scope 不够、`account_id` 缺失，还是跨域名组合不成立。

[实施计划 §2](实施计划.md) 列了四个「做 Q4 时一起做掉」的搭车项，它们已经并进下表。
**两项的位置是强制的，不能挪**：

- **4a₀ 的 5 小时计时必须最先启动。** 实施计划的原话是「Q4 一开始就要挂上，不然会变成
  S6 的阻塞项」。它是纯等待，越早挂上越不占用总时长。
- **4f 的限流试探必须放在最后。** 试出最小刷新间隔意味着**反复调 usage 直到 429**，
  一旦把账号打进退避期，4d 的 scope 削减实验就没法做了。

| 阶段 | 做什么 | 产出 / 供给 |
|---|---|---|
| **4a₀** | 记下此刻，并**停止使用 Claude Code 对话**，挂起 5 小时计时 | 4e 的前置 |
| 4a | Codex 全量 scope 端到端 | 200 + 原始 JSON + `account_id` 有无 |
| 4b | Claude 全量 scope 端到端 | 200 + 原始 JSON |
| 4c | 结构比对（4.5） | key diff 结果 |
| 4c′ | 两份完整响应脱敏存 fixture | 供 S4——至今无人见过这两个接口的完整响应 |
| 4d | scope 削减实验 | 最小可用集合，供 S2 |
| 4e | 满 5 小时后重调 Claude usage，记录 `session` 的 `is_active` 与 `resets_at` 关系 | 协议观察，不影响 S6 文案 |
| **4f** | **（最后做）** 递增频率调 usage 直到 429，记录触发阈值与 `Retry-After` | 最小安全刷新间隔，供 S5 |

4e 不再承担产品文案决策：真实响应已证明 `is_active:false` 可以与已开始的重置倒计时
并存。移动端按百分比与 `resets_at` 展示，字段变化只作为协议观察记录，见
[移动端额度展示要求 §4.2](移动端额度展示要求.md)。

4f 拿不到结果也可以收工：代价不对称，高估限流只是刷新慢一点，低估会导致功能整体不可用，
所以缺数据时按**严**的假设配参数。

4d 的重点是 Q2 末尾那个悬案：**`user:inference`（Claude）和 `api.connectors.invoke`（Codex）能否去掉**。这两项是「能直接消耗账号额度调模型」的权限，直接关系到「只读额度」原则能守到什么程度。每削一次都要重走一次授权，这是唯一验证方式。

削不掉也是有价值的结论——把「无法规避」从推断升级为实测。

#### 4.5 结构比对方法

真实账号只有一种状态，桌面端 fixture 是多场景合集，**两者不可能完全相同**，不要按「完全一致」判定。

提取 key 路径集合比对：

```bash
jq -r 'paths(scalars)|join(".")' fixtures/raw/codex-usage.json | sort
```

拿它与 cc-trace 的 `fixtures/providers/codex/usage-normal.json`（Claude 用 `usage-mixed.json`）的同样输出做 diff。

**判定：实测 key ⊆ fixture key，且没有出现 fixture 里不存在的新 key。**
缺 key 属正常（该账号没有那种额度窗口）；**出现新 key 才是需要处理的信号**，说明移动端拿到的响应与桌面端不同。

#### 4.6 判定检查表

- [ ] Codex：code → token 返回 200，响应含 `access_token` 与 `refresh_token`
- [ ] Codex：`chatgpt_account_id` 能从 access_token 或 id_token 的 claim 解出
- [ ] Codex：usage 返回 200，key ⊆ 桌面端 fixture
- [ ] Claude：code → token 返回 200（请求体为 JSON 且含 `state`）
- [ ] Claude：usage 返回 200（带 `anthropic-beta`），key ⊆ 桌面端 fixture
- [ ] 两端各记录一次 token 过期时间（解 JWT 的 `exp`），供 Q3 的刷新调度参考

> 第二项同时答掉 [实施计划 §5](实施计划.md) 最后一行「移动端身份的取得路径」。
> 那份表把它挂在 S2，但实际上 **Q4 就必须解决**——Codex 的 usage 请求依赖 `account_id`，
> 拿不到它 Q4 本身就过不了。结论出来后回填实施计划，不要等到 S2。

#### 4.7 失败分支

| 现象 | 最可能原因 | 回到哪一步 |
|---|---|---|
| token 交换 400 | 两家 body 格式弄反（Codex form / Claude JSON） | 脚本内修正，不回 Q2 |
| Claude token 400 | 漏了非标准的 `state` 字段 | 同上 |
| token 交换 400 且提示 redirect | token 请求的 `redirect_uri` 与 authorize 时不一致 | 脚本内修正 |
| usage 4xx 且 `account_id: absent` | Codex 专有，JWT claim 里没有 | **新问题，回 Q2 补 authorize 参数** |
| usage 4xx 且 `account_id: present` | scope 不足 | 回 Q2 加 scope，重走授权 |
| usage 200 但出现新 key | 移动端 scope 与桌面端不同 | 不算失败，记录差异后继续 |

#### 4.8 基线验证记录

**通过（2026-07-28，macOS）。** 两个 Provider 都完成了系统浏览器授权、loopback 回调、
code 换 token 与 usage 请求，usage 均返回 HTTP 200 且是 JSON。

- Codex：token 响应含 `access_token`、`refresh_token`、`id_token`；`chatgpt_account_id`
  可从 access token 的 claim 解出。说明移动端不依赖 `auth.json` 也能构造
  `ChatGPT-Account-Id` 请求头。
- Claude：跨 `claude.com` authorize 与 `platform.claude.com` token endpoint 的组合成立；
  token 响应含 access / refresh token。access token 不是 JWT，因此没有可记录的 `exp` claim。
- Claude Code 2.1.212 官方客户端会在登录后请求
  `GET https://api.anthropic.com/api/oauth/profile`，并从 `account.uuid` /
  `account.email` 取得身份；移动端已按相同链路实现，真实手机响应仍待 Q3 / Q4 验收。
- 两份完整 usage 响应与去除 `Set-Cookie` 的响应头仅本地保留在 `fixtures/raw/`（权限 `0600`），
  文件名与完整 scope 见 [`fixtures/采集记录.md`](../fixtures/采集记录.md)。token 响应只记录字段
  结构与字符串长度，未落盘任何值。

字段路径比对发现桌面端现有 fixture 是人工构造的子集：Codex 还返回 `credits`、
`rate_limit_reset_credits` 等字段；Claude 还返回 `extra_usage`、`spend` 以及动态窗口的
`group` / `severity` 元数据。根据 4.7，这不是 Q4 失败，但 S4 必须以本次完整响应的结构为准，
不能只假定桌面端手写 fixture 覆盖完整协议。

**尚未完成：**最小 scope 削减、5 小时后的 Claude `is_active` 复测、429 / `Retry-After`
限流试探，以及人工白名单脱敏后是否将 fixture 纳入版本库。最后一项会产生账号实际额度数据；
在明确同意前，只保留 Git 忽略的本地原始证据，不向 `fixtures/providers/` 写入真实数值。

## 验证方式

先用**最小脚本**验证，不要在 Flutter 应用工程里做。Q1 和 Q2 完全可以在桌面命令行上
跑通（loopback 在哪都一样），确认协议层可行之后，Q3 才需要真机。

顺序：Q2 → Q1 → Q4 → Q3。前三个在电脑上做，只有 Q3 必须上真机。

## 纪律

以下几条在验证阶段就要守住，不能等到写正式代码：

- access token、refresh token、authorization code 一律不进日志、不进剪贴板、不进 URL 之外的任何地方
- 真实响应存为**脱敏** fixture；原始响应不入库（`.gitignore` 已排除 `fixtures/raw/`）
- 用自己的账号验证，不使用他人凭据
- 只读额度，不碰对话内容

## 证据留存

上面四条是原则，这一节是执行细则。**验证过程中的接口数据要留存，但不是「全都存一份」**——按敏感度分三档，处置完全不同。

### 为什么要留

整个方案建立在冒用官方 CLI client_id 之上（见「结论」表格末行），对方随时可能收紧。

将来接口一变，第一个要回答的问题永远是「**是我们写错了，还是对方改了**」。没有带日期的原始快照，就只能先怀疑自己的代码，排查成本极高。留存的目的是**建立基准线**，不是留个纪念。

这个目的也决定了粒度：只存成功响应不够，要存到能重放对比的程度。

### 三档

| 档 | 内容 | 处置 |
|---|---|---|
| **A · 存全量** | usage 响应体、HTTP 响应头（去 `set-cookie`）、错误响应体、authorize 被拒时的跳转 URL | 原样落 `fixtures/raw/`，脱敏后入库 |
| **B · 只存结构** | token 交换的响应 | **只记字段名、类型、长度；值一律不落盘** |
| **C · 不存** | access / refresh token、id_token 原文、authorization code、`Authorization` 头的值 | 内存中用完即弃 |

**B 档必须单独强调：`fixtures/raw/` 不是纪律豁免区。**

它豁免的只是「未脱敏的额度数据」，不豁免凭据。token 响应即使写进被 gitignore 的目录，也是在磁盘上留下了明文 refresh_token，而 refresh_token 的有效期很长。**任何情况下都不得先 dump 再筛选。**

id_token 是 B 档里最容易出事的一项：为了查 `chatgpt_account_id`（见 4.2 第三个未知数），必然要解它的 payload。**解出的 claim 键名可以记录，值不可以。**

### 失败响应比成功响应更值钱

Q1 已经证明了这一点。信息量最大的不是那两个成功的 code，而是这句：

```text
Redirect URI cctrace://callback is not supported by client.
```

「not supported by **client**」直接指向 client_id 的注册项，一句话定死了自定义 scheme 这条路。而 Codex 侧只给了个 `unknown_error`——**这个「什么都没说」本身也是必须记录的事实**，它意味着 Codex 的排查只能靠控制变量，不能靠读报错。

因此 Q4 采集时，**故意制造的失败要和成功一样认真地留存**：故意少一个 scope、故意不带 `ChatGPT-Account-Id`、故意用已过期的 code。这几发失败响应的价值，大概率超过成功的那一发。

### 脱敏用白名单，分两步

黑名单（删掉已知敏感字段）会漏掉新出现的字段，**不得使用**。白名单（只保留已知安全字段）是安全的，但会把 4.5 要找的「新 key」一并吃掉。

两步走，与现有 `.gitignore` 的设计一致：

```text
① 完整响应 → fixtures/raw/         已 gitignore，仅本地留存，用于发现新 key
② 人工过目 → fixtures/providers/   白名单过滤后入库
```

`fixtures/raw/` 本来就被排除，这个两阶段结构是预设好的，不需要新造概念。

额度数字本身不敏感（那正是要验证的东西），脱敏对象是可能混在响应里的 org id、邮箱、账号标识等。

### 每份快照都要带元数据

否则半年后无从判断它是何时、用什么账号、什么 scope 采集的。但元数据**不能塞进 JSON 本身**——fixture 要能直接喂给解析器。

单独记在 `fixtures/采集记录.md`，沿用下面「验证记录」表的格式：

| 文件 | 日期 | Provider | 账号类型 | scope | 结果 |
|---|---|---|---|---|---|

`scope` 一列是关键：4d 的削减实验中每发响应对应哪组 scope，不记下来实验就白做了。

## 结论

> **Q1、Q2 与 Q4 基线通过（2026-07-28，macOS）；Q3 未开始，Q4 补充实验进行中。**
> 四个问题全部通过之前，不开始界面实现。

协议层已经跑通：两个 Provider 都能用官方 CLI 的 client_id 构造出被接受的 authorize
请求，并通过 loopback 回调拿到 authorization code。**移动端登录不存在协议层面的
不可行**，当前产品形态与 ADR-0002 不需要因此复审。

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
| Q1 拿到 code | 2026-07-28 | macOS | 本地 loopback server + 账号持有人真实登录 |
| Q1 补测（scheme / IP 字面量） | 2026-07-28 | macOS | 同上，两项 Claude 侧均被拒 |
| Q3 | 2026-07-29 | Android 观察到 localhost Resolver；修复待验证，iOS 未验证 | Custom Tabs Session / 二段回跳已编码，arm64 Release 已构建 |
| Q4 基线 | 2026-07-28 | macOS | 系统浏览器 + 本地 loopback；两家 token / usage 均为 200，完整 usage 证据仅本地留存 |
| Q4 补充实验 | — | macOS | 最小 scope、5 小时 `is_active`、429 限流均未完成 |

Q1 白名单验证中的 authorization code 未落盘、未换取 token；Q4 基线已完成 token 交换，
但 token 与完整原始响应仅在 Git 忽略的本地证据目录中短暂处理，不进入仓库。整个验证过程
未读写 `~/.codex` 与 `~/.claude` 的任何凭据。

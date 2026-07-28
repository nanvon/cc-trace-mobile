# OAuth 可行性验证

> 状态：**未开始**
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

这两个 `client_id` 属于 Codex CLI 和 Claude Code 官方客户端，是公开值。

**已验证的只有 token 刷新和 usage 查询这两步。** authorize 端点、PKCE 参数、redirect_uri 白名单——全部未知。

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

### Q2 · authorize 端点和 PKCE 参数是什么？

需要确认 authorize URL、必需的 query 参数、PKCE 的 `code_challenge_method`（预期 `S256`）、以及 `scope` 的最小可用集合。

10 号参考文档里观察到过一组 Claude scope（`user:profile`、`user:inference`、`user:sessions:claude_code` 等），但那是静态字符串。**按 usage 接口实际需要申请最小 scope，不照抄。**

**判定**：能构造出被接受的 authorize 请求即通过。

### Q3 · 本地 loopback server 在两个平台上都能接住回调吗？

- iOS：`ASWebAuthenticationSession` 打开授权页；应用在前台时本地 server 能否稳定监听
- Android：Chrome Custom Tabs；后台省电策略是否会掐掉监听
- 端口被占用、用户中途取消、重复回调、超时

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

> 待验证。四个问题全部通过之前，不开始界面实现。

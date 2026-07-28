# CC Trace Mobile

在手机上查看 Codex 与 Claude Code 的订阅额度。

> 状态：**骨架阶段**。OAuth 协议层与 usage 基线已验证，平台层未验证，没有可运行的应用。

## 这是什么

[CC Trace](https://github.com/nanvon/cc-trace) 的移动端。桌面端常驻在 macOS Menu Bar / Windows Tray，读取本机凭据显示额度；移动端做同一件事的手机版本。

**它不是桌面端的移植。** 两者只共享品牌、视觉语言和额度语义，代码、数据和仓库完全独立，原因见 [ADR-0001](docs/决策/ADR-0001-独立仓库与技术栈选型.md)。

## 技术栈

| 项 | 选型 |
|---|---|
| 框架 | Tauri 2 Mobile |
| 前端 | Vue 3 + TypeScript + Vite + Pinia |
| 核心 | Rust |
| 目标平台 | iOS、Android |

## 当前进展与未知

移动端**读不到**本机的 `~/.codex` 和 `~/.claude`——桌面端赖以工作的凭据来源在手机上不存在。因此移动端必须自己实现完整的 OAuth 登录，而这是相对桌面端唯一全新的部分。

**这条链路的协议层已经跑通。** 2026-07-28 在 macOS 上实测，两个 Provider 都能通过 loopback 回调拿到 authorization code——原本那个「Provider 未必把第三方移动端的 redirect URI 列进白名单」的否决级风险不成立，[ADR-0001](docs/决策/ADR-0001-独立仓库与技术栈选型.md) 不需要复审。

剩下的未知从「能不能做」变成了「稳不稳」：

| 未知 | 归属 |
|---|---|
| 手机上跑本地 HTTP server 接住回调，两个平台都稳吗 | [Q3](docs/OAuth可行性验证.md)，未验证 |
| 换到的 token 能调通 usage 接口吗 | [Q4](docs/OAuth可行性验证.md)，基线已通过；scope / 限流 / `is_active` 补充实验进行中 |
| 免费 Apple ID 下 Tauri 2 Mobile 装得上 iPhone 吗 | [S1](docs/实施计划.md)，未验证 |
| 冒用官方 CLI 的 client_id，对方随时可以收紧 | 产品风险，无法消除 |

最后一条不是我们引入的，是「仿照 Nowdex」这条路径本身的代价。

所以下一步仍然不是写界面，是 Q3 的双平台 loopback 真机验证；Q4 的最小 scope、限流和
`is_active` 补充实验也需继续完成。步骤拆分见[实施计划](docs/实施计划.md)。

## 开发环境

已就绪：Node 24、pnpm 11、Rust 1.97、Xcode 26
待安装：Android SDK + NDK

## 许可证

[MIT](LICENSE)

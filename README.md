# CC Trace Mobile

在手机上查看 Codex 与 Claude Code 的订阅额度。

> 状态：**骨架阶段**。技术可行性尚未验证，没有可运行的应用。

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

## 当前最大的未知

移动端**读不到**本机的 `~/.codex` 和 `~/.claude`——桌面端赖以工作的凭据来源在手机上不存在。因此移动端必须自己实现完整的 OAuth 登录，而这条链路目前**一步都没有验证过**。

其中有一个可能直接否决整个项目的风险：**Provider 未必把第三方移动端的 redirect URI 列进白名单。**

所以下一步不是写界面，是跑通登录。见 [OAuth 可行性验证](docs/OAuth可行性验证.md)。

## 开发环境

已就绪：Node 24、pnpm 11、Rust 1.97、Xcode 26
待安装：Android SDK + NDK

## 许可证

[MIT](LICENSE)

# CC Trace Mobile

在手机上查看 Codex 与 Claude Code 的订阅额度。

> 状态：**S1 / Q3 真机验证工具开发中**。OAuth 协议层与 usage 基线已验证；Flutter
> 最小工程与 Q3 静态实现已完成，但尚未构建或真机验证，也没有正式产品功能。

## 这是什么

[CC Trace](https://github.com/nanvon/cc-trace) 的移动端。桌面端常驻在 macOS Menu Bar / Windows Tray，读取本机凭据显示额度；移动端做同一件事的手机版本。

**它不是桌面端的移植。** 两者只共享品牌、视觉语言和额度语义，代码、数据和仓库完全独立，原因见 [ADR-0001](docs/决策/ADR-0001-独立仓库与技术栈选型.md)。

## 技术栈

| 项 | 选型 |
|---|---|
| 框架 | Flutter Stable |
| 语言 | Dart |
| 目标平台 | iOS、Android |

技术栈决定见 [ADR-0002](docs/决策/ADR-0002-Flutter移动端技术栈.md)。仓库与桌面端的
独立边界仍由 [ADR-0001](docs/决策/ADR-0001-独立仓库与技术栈选型.md) 约束。

## 当前进展与未知

移动端**读不到**本机的 `~/.codex` 和 `~/.claude`——桌面端赖以工作的凭据来源在手机上不存在。因此移动端必须自己实现完整的 OAuth 登录，而这是相对桌面端唯一全新的部分。

**这条链路的协议层已经跑通。** 2026-07-28 在 macOS 上实测，两个 Provider 都能通过
loopback 回调拿到 authorization code——原本那个「Provider 未必把第三方移动端的
redirect URI 列进白名单」的否决级风险不成立。

剩下的未知从「能不能做」变成了「稳不稳」：

| 未知 | 归属 |
|---|---|
| 手机上跑本地 HTTP server 接住回调，两个平台都稳吗 | [Q3](docs/OAuth可行性验证.md)，未验证 |
| 换到的 token 能调通 usage 接口吗 | [Q4](docs/OAuth可行性验证.md)，基线已通过；scope / 限流 / `is_active` 补充实验进行中 |
| Flutter 应用在免费 Apple ID 下的真机部署与 7 天重签流程 | [S1](docs/实施计划.md)，未验证 |
| 冒用官方 CLI 的 client_id，对方随时可以收紧 | 产品风险，无法消除 |

最后一条不是我们引入的，是「仿照 Nowdex」这条路径本身的代价。

当前只开发承载 Q3 的最小 Flutter 真机验证工具，不实现额度、导航、缓存、正式 Provider
或 token 持久化。由于暂时没有目标真机条件，空壳部署与 Q3 双平台验收仍未执行。Q4 的
最小 scope、限流和 `is_active` 补充实验也需继续完成。步骤拆分见
[实施计划](docs/实施计划.md)。

## 开发环境

固定环境基线见
[Flutter 迁移与环境准备计划](docs/Flutter迁移与环境准备计划.md)。当前应用工程只允许包含
[S1 / Q3 专项计划](docs/S1-Q3真机验证专项计划.md)规定的验证代码。

## 许可证

[MIT](LICENSE)

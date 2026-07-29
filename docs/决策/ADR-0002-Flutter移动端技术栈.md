# ADR-0002：Flutter 移动端技术栈

- 状态：已确认
- 日期：2026-07-29
- 取代：[ADR-0001](ADR-0001-独立仓库与技术栈选型.md) 的技术栈部分
- 相关：cc-trace 的 [ADR-0016](https://github.com/nanvon/cc-trace/blob/main/docs/决策/ADR-0016-不购买Apple开发者账号.md)

## 背景

CC Trace Mobile 已明确为独立于桌面端的产品。两端只沿用品牌、设计 token、额度语义和
Provider 协议事实；移动端不复用 Vue、Rust、Tauri IPC、桌面壳或生命周期。

原选型 Tauri 2 Mobile 的主要收益是复用桌面端技术栈。这个前提消失后，移动端继续承担
WebView、Rust 和双平台插件三层复杂度，已经没有相称的共享收益。

## 决策

1. 应用技术栈改为 **Flutter Stable + Dart**，Android 优先，iOS 保留在同一代码库。
2. 仓库继续独立，不与桌面端组成 monorepo，也不共享运行时代码、凭据、数据库或代理。
3. Provider 接口路径、字段解析和额度归一化仍以桌面端已验证实现为事实来源，但在 Dart
   中独立实现。
4. `verify/oauth/` 的 Q4 Rust 脚手架作为独立、可复核的协议验证资产保留，不复用为
   Flutter 应用代码。
5. Q3 仍必须在 iOS 与 Android 真机应用内验证。`dart:io HttpServer` 提供 loopback API
   只说明具备实现手段，不代表真实浏览器、应用生命周期和回调链路已经通过。

## 理由

- Flutter 提供移动优先的一套 UI 与业务代码，符合 Android 优先、iOS 同库保留的产品边界。
- Dart 自带 `HttpServer`，能够承载 Q3 必须验证的 loopback OAuth server。
- 移除 WebView 前端、Rust 核心与 Tauri IPC 的跨层组合后，移动端的调试和生命周期边界更直接。
- 原生浏览器、安全存储等平台能力仍允许通过 Flutter 插件或少量 Kotlin / Swift 桥接实现，
  不要求整套业务逻辑分平台重写。

## 代价

- Flutter SDK 本身较大；应用技术栈更简单不等于本机工具链占用最小。
- Android 仍依赖 JDK、Android SDK、Build Tools、NDK、CMake 与 Gradle。
- iOS 仍依赖 Xcode 与 Apple 签名。Flutter 不绕过 Personal Team 的 7 天重签限制，
  也不改变“不购买 Apple 开发者会员”的硬约束。
- 原生浏览器、安全存储等能力仍可能需要 Flutter 插件或少量 Kotlin / Swift。
- `dart:io HttpServer` 支持 loopback 只是 API 能力；iOS / Android 的 OAuth 真机链路
  仍是 Q3 的未验证项。
- Q4 Rust 脚手架与未来 Dart 实现形成两份实现。Rust 只保留为证据工具，协议变化时两边
  都需要核对。
- Gradle、插件与平台工具链仍可能带来版本兼容问题；本决定不把 Flutter 描述为零原生依赖。

## 分发约束

- Android 可直接分发 APK。
- iOS 仅本人使用免费 Apple ID / Personal Team 真机调试，接受 7 天重签。
- 不提出任何以购买 Apple 开发者账号或代码签名证书为前提的方案。

## 复审条件

- Q3 证明 Flutter 应用无法在任一目标平台稳定完成系统浏览器 + loopback 回调链路。
- 必需的原生浏览器或安全存储能力只能通过高维护成本的双平台自研桥接完成。
- Android 优先、iOS 同库保留的产品边界发生变化。
- Flutter / Dart 与平台工具链的长期维护成本超过双原生或其它方案。
- Provider 收紧 client_id、redirect_uri 或 usage 接口，使当前产品前提失效。

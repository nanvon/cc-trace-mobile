<p align="center">
  <img src="ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png" width="128" alt="CC Trace Mobile 图标">
</p>

<h1 align="center">CC Trace Mobile</h1>

<p align="center">
  <b>iOS / Android 移动端 AI 额度监控看板</b><br>
  随身追踪 Codex 与 Claude Code 配额用量、重置倒计时与额外用量，无需折返电脑。
</p>

<p align="center">
  <img alt="iOS" src="https://img.shields.io/badge/iOS-13%2B-000000?logo=apple&logoColor=white">
  <img alt="Android" src="https://img.shields.io/badge/Android-arm64-3DDC84?logo=android&logoColor=white">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white">
  <a href="https://github.com/nanvon/cc-trace-mobile/releases/latest"><img alt="Latest Release" src="https://img.shields.io/github/v/release/nanvon/cc-trace-mobile?color=brightgreen"></a>
  <img alt="License" src="https://img.shields.io/badge/license-MIT-orange">
</p>

<p align="center">
  <a href="https://github.com/nanvon/cc-trace-mobile/releases/latest">下载安装</a> ·
  <a href="#-核心特性">功能特性</a> ·
  <a href="#-快速安装">安装指南</a> ·
  <a href="#-数据与隐私安全">安全说明</a> ·
  <a href="#-从源码构建">从源码构建</a> ·
  <a href="https://github.com/nanvon/cc-trace-mobile/issues">问题反馈</a> ·
  <a href="README_EN.md">English</a>
</p>

---

## ✨ 核心特性

### ⚡ 双引擎额度透视
* **多时间窗口监控** — 实时拉取 Codex 与 Claude Code 的 5 小时会话窗口及每周额度窗口，展示精确剩余百分比与重置倒计时。
* **四档状态色进度条** — 剩余额度按健康度分档着色（剩余 >50% 绿、20%~50% 黄、<20% 橙、0% 红），余量状态一目了然。
* **额外额度与用量追踪** — 自动探测并独立展示 Codex 的 Reset Credits 额外额度点数，以及 Claude Code 本月额外用量的已花金额、预算上限与消耗占比。
* **模型级专项额度** — 完整支持解析 Claude Code 高级套餐中的模型专属周额度窗口（如 Opus / Sonnet / Haiku 专项额度）。

### 🔐 原生授权与本地存储
* **标准 OAuth 2.0 PKCE** — 调起系统外部独立浏览器在 Provider 官方域名完成登录，应用内不接收、不存储用户账号密码。
* **本地回环安全回调** — 内置本地 HTTP 回环服务器接收重定向回调，端口占用自动顺延（Codex 1455 / 1457，Claude 41999 / 41998 / 41997）。
* **硬件级安全存储** — 访问凭据严格保存在 iOS Keychain（仅本设备解锁可读）与 Android Keystore（加密命名空间 `cc_trace_mobile`）。
* **独立多账号登录** — Codex 与 Claude Code 相互解耦，可单独登录其中一个服务，退出登录时自动清除对应凭据与额度缓存。

### 🍃 克制低耗的运行策略
* **前台纯净运行** — 自动刷新仅在前台激活时运行，支持自定义刷新间隔（15 / 30 / 60 分钟，默认 30 分钟），零后台常驻轮询、零系统通知打扰。
* **请求节流与指数退避** — 手动下拉刷新具备 1 分钟最小节流保护；遭遇 Provider 429 限流时自动遵循梯度指数退避，严防账号被限频。
* **三维状态契约** — 采用「活动状态 / 快照新鲜度 / 失败原因」三维状态表达；网络波动或异常时保留最近一次有效快照并标注抓取时间，绝不伪装为最新数据。
* **Android 登录保活与诊断** — 在 Android 端提供登录期短时前台服务保活（防止切到浏览器时后台进程被杀）、应用内浏览器选择器及登录排错诊断日志。

### 🎨 现代化设计规范
* **HeroUI 视觉系统** — 继承桌面端 HeroUI 设计语言与 Slate 冷灰调性，提供极简圆润、低视觉噪点的界面质感。
* **深浅主题自适应** — 支持跟随系统、强制浅色、强制深色三档外观偏好；在 Android 15 及更高版本中原生支持 edge-to-edge 全面屏布局。

---

## 📦 快速安装

> **支持平台**：iOS 13.0+ · Android (arm64-v8a)<br>
> **前置要求**：拥有 Codex 或 Claude Code 的有效付费订阅（至少登录一个）。

### Android (推荐)
从 [Releases 页面](https://github.com/nanvon/cc-trace-mobile/releases/latest) 下载最新版本的 `CC-Trace-Mobile_<版本>_Android-arm64.apk` 直接安装：
- APK 经过正式 Release 密钥签名，并随附同名 `.sha256` 校验文件供完整性核验。
- 首次安装时请在系统设置中允许「安装未知来源应用」。

### iOS (自签安装)
根据项目安全与分发原则，本项目不购买 Apple 开发者计划，**不提供 App Store、TestFlight 或预编译 IPA 分发**。支持使用**免费 Apple ID** 在本地通过 Xcode 自签编译到真机（受 Apple 限制，每 7 天需重新签名一次）：

```bash
# 1. 克隆仓库并安装依赖
git clone https://github.com/nanvon/cc-trace-mobile.git
cd cc-trace-mobile
flutter pub get --enforce-lockfile

# 2. 连上 iOS 设备并以 Release 模式运行（在 Xcode 中配置自己的 Apple ID 个人证书）
flutter run --release
```

> [!NOTE]
> **真实设备验证状态说明**
> - **Android**：正式签名 arm64 APK 构建与 59 项单元/集成测试已纳入 CI 门禁。
> - **iOS**：CI 持续验证无签名 Release 编译（`flutter build ios --release --no-codesign`）通过；真机环境建议通过免费 Apple ID 本地签名调试。

---

## 🔒 数据与隐私安全

CC Trace Mobile 坚持**本地优先与零服务端中转**架构，全流程无任何自建后端服务：

### 凭据存储与安全机制

| 服务 / 模块 | 凭据存储位置 | 读写权限 | 行为机制与安全保障 |
| :--- | :--- | :---: | :--- |
| **Codex** | iOS Keychain / Android Keystore (`cc_trace_mobile`) | 读 / 写 | 标准 OAuth 2.0 PKCE 流程；本地回环端口（1455 / 1457）接收授权码；仅向官方用量接口请求数据，临期自动续期 |
| **Claude Code** | iOS Keychain / Android Keystore (`cc_trace_mobile`) | 读 / 写 | 标准 OAuth 2.0 PKCE 流程；本地回环端口（41999 顺延）接收授权码；仅向官方用量接口请求数据 |
| **额度快照缓存** | 本机 SharedPreferences | 读 / 写 | 仅在本地持久化最近一次成功拉取的额度数值与更新时间戳，供断网离线时回显；退出登录时与安全凭据一同彻底擦除 |

### 零遥测与透明度承诺
* **无自建服务器**：应用完全没有自建后端，所有请求均直接与 OpenAI / Anthropic 官方授权及用量接口通信，不经过任何第三方代理。
* **零外部遥测与追踪**：不集成任何数据统计、崩溃分析或第三方商业 SDK，不上传用户设备标识与使用习惯。
* **内存与日志防护**：Access Token、Refresh Token、授权码（Code）在代码层面实施严格过滤，绝不输出至控制台日志、绝不进调试文件、绝不暴露于前端页面。
* **完全擦除机制**：在设置页中退出登录时，将立即清空对应服务的 Keychain / Keystore 密钥与本地快照缓存。

> [!TIP]
> 登录与额度查询对接的是官方 CLI 所采用的 Client ID 与接口规范。如需完全审阅网络通信与存储实现，欢迎[从源码自主构建](#-从源码构建)。

---

## 🔧 从源码构建

项目基于 Flutter 与 Dart 构建，保持最小化依赖设计。

### 环境准备
- **Flutter SDK**：3.24+ (Dart ^3.12.2)
- **Android 构建**：JDK 17 + Android SDK (API 34+)
- **iOS 构建**：macOS + Xcode 15+

### 本地日常开发
```bash
# 检查依赖版本并安装
flutter pub get --enforce-lockfile

# 运行全量静态检查与自动化测试
flutter analyze
flutter test

# 启动本地调试
flutter run
```

### 生产打包命令
```bash
# 构建 Android 正式 arm64 APK
flutter build apk --release --target-platform android-arm64

# 构建 iOS 无签名 Release 产物
flutter build ios --release --no-codesign
```

> [!TIP]
> 更多有关 Android 证书生成、钉扎验证与 GitHub Actions 自动发版流程，请参阅 [GitHub 自动构建与发布](docs/GitHub自动构建与发布.md) 与 [Android 正式签名与发布](docs/Android正式签名与发布.md)。

---

## 🔗 相关项目

同作者系列工具，共享同一套配额口径、状态契约与四档状态色规范：

| 项目 | 平台形态 | 技术栈 | 特点 |
| :--- | :--- | :--- | :--- |
| [**cc-bar**](https://github.com/nanvon/cc-bar) | macOS 原生菜单栏工具 | Swift / SwiftUI | 原生极低资源占用，菜单栏直显百分比，集成桌面 HUD 悬浮窗与本地会话统计 |
| [**CC Trace**](https://github.com/nanvon/cc-trace) | 桌面客户端（macOS / Windows） | Tauri / Web (HeroUI) | 跨平台桌面托盘与浮窗，支持多引擎额度与用量透视 |
| **CC Trace Mobile**（本仓库） | 移动端伴侣（iOS / Android） | Flutter / Dart | 手机端便携监控，双引擎官方 OAuth 直连，离线快照回显，克制低功耗 |

> [!NOTE]
> 三个应用各自独立运行，数据与配置在本地独立存储，互不相通，无需部署中转服务器。

---

## 📢 免责声明

本项目为开源个人工具，非 OpenAI 或 Anthropic 的官方产品，与两家公司无任何商业关联，亦未获得其官方认可或赞助。Codex、Claude 及相关商标归各自所有者所有。

---

## 📄 许可证

本项目基于 [MIT](LICENSE) 许可证开源。

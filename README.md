<p align="center">
  <img src="ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png" width="128" alt="CC Trace Mobile 图标">
</p>

<h1 align="center">CC Trace Mobile</h1>

<p align="center">iOS / Android 应用:随时查看 Codex 与 Claude Code 的剩余额度与重置时间,<br>不用回到电脑前。</p>

<p align="center">
  <img alt="iOS" src="https://img.shields.io/badge/iOS-13%2B-000000?logo=apple&logoColor=white">
  <img alt="Android" src="https://img.shields.io/badge/Android-arm64-3DDC84?logo=android&logoColor=white">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white">
  <a href="https://github.com/nanvon/cc-trace-mobile/releases/latest"><img alt="release" src="https://img.shields.io/github/v/release/nanvon/cc-trace-mobile?color=brightgreen"></a>
  <img alt="license" src="https://img.shields.io/badge/license-MIT-orange">
</p>

<p align="center">
  <a href="https://github.com/nanvon/cc-trace-mobile/releases/latest">下载</a> ·
  <a href="#-安装">安装</a> ·
  <a href="#-从源码构建">从源码构建</a> ·
  <a href="#-相关项目">相关项目</a> ·
  <a href="https://github.com/nanvon/cc-trace-mobile/issues">反馈</a> ·
  <a href="README_EN.md">English</a>
</p>

<!-- 头部截图占位:补充 docs/images/ 下的深浅色额度主屏截图后替换本注释:
<p align="center">
  <img src="docs/images/home-light.png" width="360" alt="额度总览 - 浅色模式">
  <img src="docs/images/home-dark.png" width="360" alt="额度总览 - 深色模式">
</p>
-->

## ✨ 功能

- **额度总览** —— Codex 与 Claude Code 的 5 小时 / 周窗口剩余额度与重置倒计时,进度条按余量分档变色;Codex 的额外重置次数与 Claude Code 的模型专项额度单独展示;下拉即可刷新
- **账号登录** —— 拉起系统浏览器走 Provider 官方登录页,标准 OAuth + PKCE,不在应用内输入密码;两个服务可以只登录一个
- **设置项** —— 账户登录 / 退出、外观(跟随系统 / 浅色 / 深色)、刷新间隔(15 / 30 / 60 分钟,默认 30)
- **克制的刷新** —— 自动刷新只在前台运行,不发通知、不后台轮询;手动刷新有 1 分钟节流,被限流时按梯度退避;取不到新数据时旧数据标注时间,不伪装成最新

### 📸 界面预览

<!-- 截图占位:建议补充以下素材(放 docs/images/ 下,竖屏手机截图)后替换本表格。
     1. home-light.png / home-dark.png  额度主屏(两个服务 + 进度条 + 倒计时)
     2. settings.png                    设置页(账户 / 外观 / 刷新间隔)
-->

|               额度总览                |               设置页                 |
| :-----------------------------------: | :----------------------------------: |
| _待补充 `docs/images/home-light.png`_ | _待补充 `docs/images/settings.png`_ |

## 📦 安装

🍎 要求 iOS 13 或更高,或 arm64 Android 设备;需要 Codex 或 Claude Code 的付费订阅(至少一个)。

**Android**:从 [Releases](https://github.com/nanvon/cc-trace-mobile/releases/latest) 下载 `CC-Trace-Mobile_<版本>_Android-arm64.apk` 直接安装。APK 经正式签名,附同名 `.sha256` 可校验;首次安装需在系统里允许「安装未知来源应用」。

**iOS**:没有 App Store 版本、TestFlight 或 IPA——本项目不购买 Apple 开发者账号,只支持用**免费 Apple ID** 自签安装(每 7 天需重签一次)。需要一台装好 Xcode 的 Mac:

```bash
flutter pub get
flutter run --release   # 连上设备,用你自己的 Apple ID 签名
```

> [!NOTE]
> iOS 自签到真机这条路径尚未完整验证;CI 持续验证的是 `flutter build ios --release --no-codesign` 能编译通过。Android 已在真机完成登录与额度实调的端到端验证(具体版本、设备与场景见 [当前验证状态](docs/当前验证状态.md))。

## 🔒 数据与安全

CC Trace Mobile 是为个人需求开发的开源小工具,**没有自己的服务器**——没有后端、没有遥测、没有崩溃上报:

- 只向 Codex 与 Claude Code 的官方接口请求额度数据,凭据不发给任何第三方
- 凭据保存在 iOS Keychain / Android Keystore,额度缓存只落在本机
- 不读取、不上传对话内容和代码;token 不进日志、不进缓存、不进任何调试输出
- 退出登录会同时删掉本机保存的凭据和额度缓存

> [!TIP]
> 登录与额度查询使用官方 CLI 所用的 client ID 与非公开用量接口,Provider 收紧策略时可能直接失效;如果介意,可以自行审阅代码后[从源码构建](#-从源码构建)。

## 🔧 从源码构建

技术栈:Flutter / Dart。运行时依赖只有四个:`http`、`crypto`、`flutter_secure_storage`、`shared_preferences`。

**日常开发**:`flutter pub get --enforce-lockfile` 后 `flutter run`。

**打包分发**:

```bash
flutter analyze && flutter test
flutter build apk --release --target-platform android-arm64   # Android
flutter build ios --release --no-codesign                     # iOS(无签名编译)
```

推送与 `pubspec.yaml` 版本匹配的 `v*` tag 后,CI 会用正式签名密钥构建 release APK 并创建公开 Release,详见 [GitHub 自动构建与发布](docs/GitHub自动构建与发布.md)。

## 🔗 相关项目

同一作者的三个应用,共享同一套额度口径与视觉语言:

|                                                    |                                        |
| -------------------------------------------------- | -------------------------------------- |
| [**cc-bar**](https://github.com/nanvon/cc-bar)     | macOS 原生菜单栏版(SwiftUI)          |
| [**CC Trace**](https://github.com/nanvon/cc-trace) | 桌面端 · macOS 菜单栏 / Windows 托盘   |
| **CC Trace Mobile**(本仓库)                      | 移动端 · iOS / Android                 |

三个应用相互独立,数据与设置不互通。

## 📢 免责声明

本项目不是 OpenAI 或 Anthropic 的官方产品,与两家公司无关,也未获得其认可或支持。Codex、Claude 及相关名称归各自所有者。

## 📄 许可证

[MIT](LICENSE)

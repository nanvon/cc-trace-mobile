# Flutter 迁移与环境准备计划

> 状态：**已完成（2026-07-29）**。这是 Flutter 工程创建前的历史执行计划与环境记录。
>
> 制定日期：2026-07-29
>
> 执行入口：在新对话中要求 Codex「严格按
> `docs/Flutter迁移与环境准备计划.md` 执行」。

## 1. 本次决定

`cc-trace-mobile` 仓库的应用技术栈从 **Tauri 2 Mobile + Vue 3 + Rust** 改为
**Flutter Stable + Dart**，Android 优先，iOS 保留同一代码库。

这项决定推翻 [ADR-0001](决策/ADR-0001-独立仓库与技术栈选型.md) 的技术栈部分，
但不推翻「独立仓库、独立应用、不与桌面端共享运行时代码」的边界。

现在改变判断的第一性原因：

1. 移动端和桌面端已经明确为两个独立产品，除了视觉语言和额度语义，不复用 Vue、Rust、
   Tauri IPC 或桌面端生命周期。
2. Tauri 原本最重要的收益是复用桌面端技术栈；这个前提消失后，WebView、Rust 与双平台
   原生插件的组合只会增加移动端复杂度。
3. Flutter 是移动优先的一套 UI 与业务代码，Dart 自带 `HttpServer`，适合承载本项目
   必须真机验证的 loopback OAuth；平台浏览器、安全存储等能力仍允许用少量 Kotlin / Swift
   桥接。
4. Android 是首要开发和可能分发的平台；iOS 使用免费 Apple ID 真机调试，继续遵守
   Personal Team 与 7 天重签约束，不购买开发者会员。

## 2. 本轮执行范围

下一次对话**只完成两件事**：

1. 整理仓库：保留有效研究成果，废弃未提交的 Tauri 工程，更新并提交技术决策文档。
2. 安装并配置 Flutter、Android、iOS 所需的开发环境。

明确不做：

- 不执行 `flutter create`
- 不生成 `pubspec.yaml`、`lib/`、`android/` 或 `ios/`
- 不搭 Flutter 框架
- 不写 Dart、Kotlin、Swift 或任何产品代码
- 不实现 Q3 OAuth 真机验证壳
- 不运行应用 build、test、lint、dev、模拟器或真机构建
- 不安装 Android Studio
- 不安装 Android Emulator、Android AVD 或新的 iOS Simulator Runtime
- 不修改现有网络或代理配置
- 不提交真实凭据、原始 token 或未脱敏响应
- 不 push

任何想顺带搭工程、选状态管理库、加 Flutter 插件或画页面的动作，都留给后续独立任务。

## 3. 当前基线

### 3.1 Git

当前分支与基线：

```text
main
HEAD = 4d998fa
origin/main = 4d998fa
```

仓库已有 5 个提交。当前工作区同时存在：

- 5 个已跟踪文件的未提交修改
- 一套未跟踪的 Vue / Vite / Tauri 骨架
- 未跟踪或 Git 忽略的本地包管理器依赖与缓存
- 已跟踪且有保留价值的 OAuth Rust 验证脚手架

执行时必须先重新运行：

```text
git status --short --branch
git diff --stat
```

若状态与本计划的清单不一致，先报告差异；不得用 `git clean -fdx`、`git reset --hard`
或宽泛删除命令把未知内容一起清掉。

### 3.2 开发环境

已确认：

| 项 | 当前状态 |
|---|---|
| CPU | Apple Silicon arm64 |
| Xcode | 26.6 |
| iPhoneOS SDK | 26.5 |
| JDK | Oracle JDK 17.0.10 arm64 |
| CocoaPods | 已安装，`/opt/homebrew/bin/pod` |
| Homebrew | `/opt/homebrew` |
| Flutter / Dart | 未安装 |
| Android SDK / adb / sdkmanager | 未安装 |
| 可用磁盘 | 满足本计划至少 20 GB 的要求 |

Flutter 3.44 起 iOS 默认使用 Swift Package Manager；CocoaPods 只作为不支持 SwiftPM 的插件
回退。现有 Xcode、iOS SDK、JDK 与 CocoaPods 不重复安装。

### 3.3 网络

下载使用执行环境已有的网络配置，不在公开文档记录代理软件、策略组、节点或线路信息。
Flutter 3.44.8 镜像文件的大小和校验值已与官方源核对一致。

执行时不得为完成安装而擅自切换全局路由、添加规则或改用来源不明的镜像。

## 4. 仓库整理

### 4.1 保留，不删除

以下内容是技术栈无关的研究、需求或证据，应完整保留：

```text
LICENSE
fixtures/
verify/oauth/
docs/移动端额度展示要求.md
docs/原型/额度主屏.html
```

其中：

- `verify/oauth/` 继续作为独立 Rust 验证工具存在，不属于未来 Flutter 应用。
- Rust 脚手架已完成 Q4 基线验证，不能因为应用改用 Dart 就删除。
- 不卸载开发环境中的全局 Node、pnpm、Rust 或 Cargo；其它仓库仍可能依赖它们。
- 不清理全局 Cargo、pnpm、Homebrew 或 Xcode 缓存。

### 4.2 更新后提交

| 文件 | 处理 |
|---|---|
| `docs/Flutter迁移与环境准备计划.md` | 保留本计划，执行后补实际结果 |
| `docs/决策/ADR-0001-独立仓库与技术栈选型.md` | 标为「部分废止」，说明独立仓库决策继续有效，技术栈由 ADR-0002 取代 |
| `docs/决策/ADR-0002-Flutter移动端技术栈.md` | 新增，记录 Flutter 决策、理由、代价、复审条件 |
| `README.md` | 技术栈改为 Flutter + Dart；状态改为迁移与环境准备；删除 Tauri / Vue / Pinia 描述 |
| `.gitignore` | 删除 Node / Vite / Tauri 专用规则与本次临时缓存规则，保留验证资产、安全与移动端构建产物规则 |
| `AGENTS.md` | 保留并提交；把 Q3 承载物由 Tauri 改为 Flutter，当前阶段改为「环境准备，尚未搭框架」 |
| `CLAUDE.md` | 与 `AGENTS.md` 的产品与阶段事实保持一致 |
| `docs/OAuth可行性验证.md` | Q3 承载物改为 Flutter 真机应用；Q4 Rust 工具改为「独立验证资产，不复用为应用代码」 |
| `docs/实施计划.md` | S1 改为 Flutter 真机验证框架；状态重置为「环境准备中，框架未搭建」 |
| `docs/移动端额度展示要求.md` | 「不进 Tauri 工程」改为「不进 Flutter 应用工程」 |
| `docs/原型/额度主屏.html` | 顶部注释同步改为 Flutter |
| `verify/oauth/README.md` | 「不是 Tauri 工程的一部分」改为「不是 Flutter 应用的一部分」 |

文档改写必须保留以下事实：

- Q1、Q2、Q4 已经得到的 OAuth 结论
- Q4 仍未完成的 scope、429、脱敏 fixture 与 `is_active` 协议观察工作
- Q3 仍需 iOS / Android 真机验证
- Codex 固定 1455 / 1457 端口、Claude 当前验证端口与取消 / 超时 / 重复回调要求
- access token、refresh token、authorization code 不进日志、不落盘
- Android 可直接分发 APK；iOS 只用免费 Apple ID 和 7 天重签
- 桌面端与移动端独立仓库、独立应用、不同凭据来源

需要修正的旧表述：

- 不再声称 Q4 Rust 代码「与最终实现同语言」或「Q3 可直接复用」
- 不再声称 iOS Tauri 原生工程已经生成
- 不再讨论 Tauri Keychain / Keystore 插件
- 不再把「Tauri 能否装进 iPhone」当作 S1 的证伪目标
- 不把 Flutter 的平台可行性写成已验证；Q3 真机结论仍是未验证

### 4.3 废弃并移入废纸篓

以下都是未跟踪或已忽略的 Tauri 尝试与本地生成物，没有独立研究价值。使用 `trash`，
按明确路径处理；不使用 `rm`，不使用通配符：

```text
.cache/
.pnpm-store/
node_modules/
.claude/
.codex/
.vscode/
.DS_Store
index.html
package.json
pnpm-lock.yaml
pnpm-workspace.yaml
public/
src/
src-tauri/
tsconfig.json
tsconfig.node.json
vite.config.ts
```

说明：

- `src-tauri/` 包含默认图标、空壳 Rust 代码和已生成的 Apple 工程，整体废弃。
- `src/App.vue` 只是临时说明页，没有独特产品设计；不迁译成 Flutter。
- `.vscode/extensions.json` 只推荐 Vue、Tauri 和 rust-analyzer，随旧骨架废弃；后续搭 Flutter
  工程时再决定是否加入 Dart / Flutter 推荐扩展。
- `.claude/skills/.gitkeep` 与空 `.codex/` 没有项目资产，随本次清理废弃。
- `node_modules/` 约 75 MiB、`.cache/` 约 52 MiB，仅是本地依赖与缓存。

### 4.4 `.gitignore`

当前未提交的 `.gitignore` 改动只新增：

```text
.cache/
.pnpm-store/
```

这两项服务于已废弃的本地 pnpm 尝试，清理真实目录后删除。

同时删除已跟踪 `.gitignore` 中不再适用的规则：

```text
npm-debug.log*
yarn-debug.log*
pnpm-debug.log*
node_modules
dist
dist-ssr
src-tauri/gen/
```

保留通用日志、Rust `target/`、Android / iOS 构建产物、凭据、真实响应和编辑器规则。

本轮不手写 Flutter `.gitignore`。后续正式执行 `flutter create` 时，以 Flutter 3.44.8
生成模板为基线，再与本仓库的凭据和 fixture 忽略规则合并。

### 4.5 ADR-0002 必须说明的代价

新 ADR 不能只写 Flutter 的优点，必须同时记录：

- Flutter SDK 本身较大，应用技术栈简单不等于工具链磁盘最小。
- Android 仍依赖 JDK、Android SDK、Build Tools、NDK、CMake 与 Gradle。
- iOS 仍依赖 Xcode 与 Apple 签名，Flutter 不绕过 7 天重签。
- 原生浏览器、安全存储等能力仍可能需要 Flutter 插件或少量 Kotlin / Swift。
- `dart:io HttpServer` 支持 loopback 只是 API 能力，不等于两个平台的 OAuth 真机链路已经通过。
- Q4 Rust 验证脚手架与未来 Dart 实现形成两份实现，Rust 只保留为可复核证据工具。

### 4.6 提交边界

完成文档改写与废弃文件清理后：

1. 运行 `git diff --check`。
2. 检查 `git status --short`。
3. 精确 stage 本节列出的文档和规范文件。
4. 不 stage `fixtures/raw/`、下载文件、SDK、缓存或任何凭据。
5. 创建一个中文提交：

```text
切换移动端技术栈为 Flutter
```

6. 不 push。

由于 Tauri 骨架从未被 Git 跟踪，废弃它不会产生删除 diff；ADR 和本计划负责保留这次决策记录。

仓库整理完成判定：

- `git status --short` 为空
- Git 中不存在 Vue、Vite、Tauri 应用骨架
- `rg` 搜到的 `Tauri` 只允许出现在历史 ADR、迁移理由或「已废弃」语境
- OAuth Rust 验证脚手架仍在
- 尚不存在 Flutter 应用骨架

## 5. Flutter 与移动端工具链安装

只有仓库整理提交完成且工作区干净后，才开始本节。

### 5.1 固定版本与安装位置

本轮固定：

| 项 | 版本 / 路径 |
|---|---|
| Flutter | 3.44.8 Stable |
| Dart | 3.12.2，由 Flutter 自带 |
| Flutter SDK | `$HOME/Developer/flutter` |
| Android SDK | `$HOME/Library/Android/sdk` |
| Android Platform | 36 |
| Android Build Tools | 36.1.0 |
| Android Platform Tools | stable |
| Android NDK | 28.2.13676358（r28c） |
| CMake | 3.22.1 |
| Java | 现有 JDK 17.0.10 |
| Xcode | 现有 26.6 |

不单独安装 Dart、Gradle、Kotlin、Swift、Node、Rust、Android Studio 或模拟器。
Gradle Wrapper 和项目依赖留到真正创建 Flutter 工程后的独立任务。

### 5.2 Flutter 下载

使用已经验证为 `DIRECT` 的 CFUG 镜像：

```text
https://storage.flutter-io.cn/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.44.8-stable.zip
```

校验基线：

```text
Content-Length = 2212764034
SHA-256 = c3d6fe95078f7001d947a31d42527de91d5bfe62e4cf444a1493a2e8f1fb199d
Git revision = 058e0af2c2b57e369d905a03ac9748b0ebf543c6
```

执行要求：

1. 在 `mktemp -d` 创建的明确临时目录下载，支持断点续传。
2. 下载完成后先校验 SHA-256，再解压。
3. `$HOME/Developer/flutter` 若在执行时已经存在，不覆盖；先检查来源和版本并报告。
4. 安装成功并验证后，用 `trash` 清理下载压缩包和临时目录。

永久镜像环境：

```text
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
PUB_HOSTED_URL=https://pub.flutter-io.cn
```

将 Flutter、Android 与 JDK 环境以带开始 / 结束标记的独立区块加入
`~/.zprofile`，不得覆盖该文件的其它内容，不重复追加：

```text
# >>> cc-trace-mobile Flutter toolchain >>>
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_ROOT="$HOME/Developer/flutter"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME="/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home"
export PATH="$FLUTTER_ROOT/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
# <<< cc-trace-mobile Flutter toolchain <<<
```

修改用户目录与 shell 配置前必须走权限确认。新 shell 中验证环境变量和 PATH 生效；
不在仓库创建 `.env` 保存这些值。

### 5.3 Android Command-line Tools

固定 Apple Silicon 包：

```text
URL = https://dl.google.com/android/repository/commandlinetools-mac_arm64-15859902_latest.zip
Content-Length = 156083281
SHA-1 = c4e0dbc53f1a4ce04fc2b11d4e2c4675001a95af
```

下载后校验 SHA-1，按 Android 官方目录布局安装到：

```text
$HOME/Library/Android/sdk/cmdline-tools/latest/
```

必须保证最终存在：

```text
$HOME/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager
```

不要形成错误的双层路径：

```text
cmdline-tools/latest/cmdline-tools/bin/sdkmanager
```

### 5.4 Android SDK 包

通过上一步的 `sdkmanager`，显式指定
`--sdk_root=$HOME/Library/Android/sdk` 安装：

```text
platform-tools
platforms;android-36
build-tools;36.1.0
cmake;3.22.1
ndk;28.2.13676358
```

要求：

- 只使用 stable channel。
- 使用 `sdkmanager --licenses` 交互式阅读并接受许可证；不静默管道输入 `yes`。
- 不安装 Android Emulator、system image、AVD、LLDB 或其它 API Level。
- 不用模糊的 `ndk;28.x`，必须使用完整包 ID。
- 不设置 `NDK_HOME`；Flutter / Gradle 通过 Android SDK 中的版本目录和 `ndkVersion` 使用 NDK。
- 运行 `flutter config --android-sdk "$HOME/Library/Android/sdk"`。
- 运行 `flutter precache --android --ios`，只准备 Android 与 iOS，不预缓存 Web 或桌面目标。

Android 基础包预计下载约 1.31 GB；执行期间还需为元数据和误差预留流量。

如果 Android 下载失败或可用网络流量不足：

- 立即停止并报告已完成的包和失败 URL。
- 不私自修改现有网络或代理配置。
- 不切换来路不明的 Android SDK / NDK 镜像。
- 不为了完成任务而删掉已正确安装的 Flutter。

### 5.5 iOS

本轮只验证已有工具，不下载新的 iOS Simulator Runtime：

```text
xcode-select -p
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
pod --version
```

不在本轮登录 Apple ID，不创建证书，不签名，不连接真机。Personal Team 与 7 天重签留到
Flutter Q3 真机验证框架任务。

### 5.6 环境验收

允许运行的诊断：

```text
flutter --version
dart --version
flutter config --list
flutter doctor -v
sdkmanager --list_installed
adb version
java -version
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
pod --version
```

不允许用创建示例项目或构建 APK / IPA 来“验证环境”。

通过标准：

- Flutter 精确为 3.44.8 Stable，Dart 为 3.12.2。
- Flutter 路径为 `$HOME/Developer/flutter`。
- Android SDK 路径为 `$HOME/Library/Android/sdk`。
- Platform 36、Build Tools 36.1.0、NDK 28.2.13676358、CMake 3.22.1、
  platform-tools 全部列为已安装。
- Android licenses 已接受。
- `adb`、JDK 17、Xcode、iPhoneOS SDK 与 CocoaPods 可被找到。
- `flutter doctor -v` 的 Flutter、Android toolchain、Xcode 三部分可用。
- 允许 Android Studio 未安装、没有模拟器、没有连接设备；这些不是失败。
- 仓库中仍没有 `pubspec.yaml`、`lib/`、`android/`、`ios/`。

### 5.7 流量与磁盘边界

预计：

| 项 | 下载 | 安装后 |
|---|---:|---:|
| Flutter 3.44.8 | 2.21 GB，CFUG 直连 | 约 4.25 GB |
| Android CLI + SDK + NDK + CMake | 约 1.31 GB | 约 4.5–5.5 GB |
| 本轮缓存与余量 | 少量 | 约 1 GB |

本轮不创建项目、不下载 Gradle 项目依赖，预计新增磁盘约 9–11 GB。
执行前要求至少 20 GB 可用；执行环境已满足。

## 6. 执行记录

执行者完成后只回填本节，不改写预定步骤。

### 6.1 仓库

```text
执行日期：2026-07-29
迁移提交：1481bf02147d851b8e2a15bf203388bb18022f40
最终 git status：执行记录提交后 clean
废弃路径是否全部进入废纸篓：是，§4.3 的 17 个明确路径均已处理
异常：无
```

### 6.2 环境

```text
Flutter：3.44.8 Stable，revision 058e0af2c2b57e369d905a03ac9748b0ebf543c6
Dart：3.12.2 Stable
Flutter 路径：$HOME/Developer/flutter
Android SDK 路径：$HOME/Library/Android/sdk
Android Platform：36
Build Tools：36.1.0
Platform Tools：37.0.0，adb 1.0.41
NDK：28.2.13676358
CMake：3.22.1
Java：Oracle JDK 17.0.10 arm64
Xcode / iPhoneOS SDK：Xcode 26.6（17F113）/ iPhoneOS SDK 26.5
CocoaPods：1.17.0
flutter doctor 摘要：Flutter、Android toolchain、Network resources 通过；Android licenses
  全部接受。Xcode 工具、iPhoneOS SDK 与 CocoaPods 可用，但因开发环境没有 Simulator Runtime，
  Xcode 项为 [!]；按本计划未下载新 Runtime。Android Studio、模拟器和连接设备均非本轮要求。
实际下载流量：未测量
实际新增磁盘：约 10.32 GiB
异常：sdkmanager 提示自身已废弃并推荐新版 Android CLI，但固定包安装与验收均成功；
  网络与代理配置未修改，未安装 Android Studio、模拟器或新 iOS Simulator Runtime
```

回填后创建第二个中文文档提交：

```text
记录 Flutter 开发环境基线
```

不 push。

## 7. 停止条件

出现任一情况，停止当前步骤并向用户报告，不自行扩展范围：

- 工作区出现本计划未列出的修改或未跟踪资产
- 发现 Tauri 骨架里存在本计划未识别的真实业务代码或不可再生资产
- Flutter 下载哈希不匹配
- 目标安装目录已存在且来源不明
- Android 许可证无法交互确认
- 下载失败且需要修改现有网络配置、改用非官方 Android 镜像或消耗超出预期的网络流量
- 安装需要覆盖现有 Xcode、JDK、CocoaPods 或其它全局工具
- `flutter doctor` 的修复建议要求安装 Android Studio、模拟器或创建示例项目
- 任何步骤开始要求编写 Flutter 应用代码

## 8. 最终完成判定

只有同时满足以下条件，下一次任务才算完成：

- 技术栈迁移文档已经提交，ADR-0002 已建立
- Tauri / Vue / Vite 未提交骨架与本地依赖已移入废纸篓
- OAuth 研究资产完整保留
- Flutter 与移动端命令行工具链安装、固定版本并通过环境诊断
- 现有网络与代理配置没有被修改
- 没有 Android Studio、模拟器或新 iOS Runtime
- 没有 Flutter 应用骨架与业务代码
- 两个计划内提交已经创建但没有 push
- `git status --short` 为空

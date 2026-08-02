<div align="center">

# CC Trace Mobile

**把 Codex 和 Claude Code 的订阅额度，装进口袋**

[![CI](https://github.com/nanvon/cc-trace-mobile/actions/workflows/ci.yml/badge.svg)](https://github.com/nanvon/cc-trace-mobile/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/nanvon/cc-trace-mobile?label=release)](https://github.com/nanvon/cc-trace-mobile/releases/latest)
[![License](https://img.shields.io/github/license/nanvon/cc-trace-mobile?label=license)](LICENSE)
![Platform](https://img.shields.io/badge/platform-iOS%2013%2B%20%7C%20Android-lightgrey)
![Flutter](https://img.shields.io/badge/Flutter-3.44.8-02569B?logo=flutter&logoColor=white)

</div>

额度快用完的时候，你通常不在电脑前。

Codex 的额度窗口和 Claude Code 的 5 小时 / 周窗口都在悄悄走，而查看它们的唯一办法是打开电脑、
跑起 CLI，或者登录官网翻页面。CC Trace Mobile 把这件事压缩成解锁手机看一眼——一屏之内，
两个 Provider，剩多少、几时重置，全部读完。

它只做这一件事：**读用量**。不发起对话，不读你的代码，不碰你的仓库。

---

## 核心特性

**两个 Provider，一屏读完**
Codex 与 Claude Code 并列展示，各自的额度窗口按重要性排序，主窗口给最大字号，次级窗口
依次向下收敛。可以只登其中一个。

**颜色即判断**
余量进度条按四档变色。不需要读数字，扫一眼颜色就知道该不该省着用。

**倒计时而不是时间戳**
重置时刻压成 `6d2h`、`1h42m`、`35m` 这样的单量级写法。你关心的是"还有多久"，
不是"2026 年 8 月 3 日 14:30"。所有数字用等宽数位，每分钟刷新时宽度不跳。

**Codex 重置次数（Reset Credits）**
攒下的重置次数单独成卡，显示可用条数和最早过期时刻；轻点展开，看每一批各自什么时候过期。

**Claude Code 模型专项额度**
套餐带模型专项额度时一并列出，用 `ALL` / `OPUS` / `SONNET` 区分同为周窗口的几条——
都写 `WEEKLY` 反而看不出差别。

**取不到就明说**
数据缺失时写「重置时间未知」，而不是留空让你猜。旧数据会标成「12m 前的数据」，
不会假装是刚刷的。

**深色模式**
跟随系统，也可以手动锁定浅色或深色。

---

## 当前状态

**Android 可以正常安装使用**，已发布经正式签名的 arm64 APK，并在真机上完成端到端验证。
**iOS 没有可分发的安装包**，只能用免费 Apple ID 自签，详见下面的安装章节。

| 部分 | 状态 |
|---|---|
| 主屏、登录、安全存储、刷新调度 | 已实现 |
| `flutter analyze` / 单元测试 / Widget 测试 | CI 每次 push 与 PR 均通过 |
| Android 正式签名 Release APK | 已发布，见 [Releases](https://github.com/nanvon/cc-trace-mobile/releases/latest) |
| Android 真机端到端（登录 + 额度实调） | **已验证通过** |
| iOS 无签名 Release 编译 | CI 每次 push 与 PR 均通过 |
| iOS 可分发安装包 | **不提供**（未购买 Apple 开发者账号） |
| iOS 真机端到端 | 未完整验证 |

实现细节与早期未验证假设见 [开发实现与静态验证记录](docs/开发实现与静态验证记录.md)。

<!-- 截图占位：请补充以下两到三张图后删除本注释。
     建议放在 docs/images/ 下，竖屏手机截图，宽度 400px 左右，深浅色各一套更好。
     1. home-screen.png     额度主屏（两个 Provider + 四档颜色进度条 + 倒计时）
     2. reset-credits.png   Codex 重置次数卡片展开态
     3. settings.png        可选：设置页（账户 / 外观 / 刷新间隔）
-->

|                  额度主屏                   |                  重置次数                   |
| :-----------------------------------------: | :-----------------------------------------: |
| _待补充 `docs/images/home-screen.png`_ | _待补充 `docs/images/reset-credits.png`_ |

---

## 系统要求

| | |
|---|---|
| **iOS** | 13.0 及以上 |
| **Android** | 未覆写 `minSdk`，跟随 Flutter 3.44.8 的默认值；发布的 APK **只包含 arm64-v8a**，不支持 32 位设备 |
| **账号** | Codex 或 Claude Code 的付费订阅（至少一个） |
| **Bundle ID** | `com.nanvon.cctrace.mobile` |

---

## 安装

### Android

从 [Releases](https://github.com/nanvon/cc-trace-mobile/releases/latest) 下载
`CC-Trace-Mobile_<版本>_Android-arm64.apk` 直接安装，APK 经正式签名，附同名 `.sha256` 可校验。
首次安装需要在系统里允许「安装未知来源应用」。

签名与发布流程见 [Android 正式签名与发布](docs/Android正式签名与发布.md)。

### iOS

**没有 App Store 版本，也不会有 TestFlight，Releases 里也没有 IPA。** 本项目不购买 Apple
开发者账号，只支持用**免费 Apple ID** 自签安装——代价是每 7 天需要重新签名一次。

CI 每次都会跑 `flutter build ios --release --no-codesign`，所以「能编译」是持续验证的；
但**自签到真机这条路径尚未完整验证**，你需要一台装好完整 iOS 平台组件的 Xcode 的 Mac。

```bash
flutter pub get
flutter run --release        # 连上你的设备，用你自己的 Apple ID 签名
```

### 从源码构建

```bash
git clone https://github.com/nanvon/cc-trace-mobile.git
cd cc-trace-mobile
flutter pub get --enforce-lockfile
flutter run
```

---

## 快速上手

**1. 登录**

点「登录 Codex」或「登录 Claude Code」，应用会拉起系统浏览器，跳转到 Provider 的
**官方登录页**。授权走标准 OAuth + PKCE（S256），完成后自动跳回应用。

两个服务可以只登一个，之后随时在设置里补另一个。

**2. 看额度**

主屏就是全部。下拉刷新，或点右上角刷新按钮。

**3. 调整**

设置页里有三组开关：

| 分组 | 可选项 |
|---|---|
| 账户 | 登录 / 重新登录 / 退出登录 |
| 外观 | 跟随系统 / 浅色 / 深色 |
| 刷新间隔 | 15 / 30 / 60 分钟（默认 30） |

退出登录会同时删掉本机保存的凭据和额度缓存。

---

## 刷新策略

Provider 对额度接口的限流比较严格，所以应用刻意刷得克制：

- **冷启动**先显示上次缓存，再决定要不要请求——不让你对着转圈等
- **手动刷新有 1 分钟节流**。太频繁会直接告诉你「刚刷新过，1 分钟后可再试」，而不是转半天再报错
- **自动刷新只在前台**。不在后台偷跑，不发通知，不占用你的电量
- **Provider 说慢点就慢点**。被限流时按 60s → 120s → 300s → 900s 递增退避；
  其他错误按 30s → 60s → 120s → 300s 退避。退避期间旧数据继续保留

---

## 隐私

本项目**没有自己的服务器**。没有后端，没有遥测，没有崩溃上报。

| | |
|---|---|
| ✅ | 只向 Codex 和 Claude Code 的官方接口请求用量数据 |
| ✅ | 凭据存在 iOS Keychain（`unlocked_this_device`）/ Android Keystore |
| ✅ | 额度缓存只落在本机 |
| ❌ | 不读取、不上传对话内容和代码 |
| ❌ | 不把凭据发给任何第三方 |
| ❌ | 不显示、也不请求账户余额与账单 |

token 不进日志、不进缓存、不进任何调试输出。真实响应只以**脱敏** fixture 形式入库。

---

## 已知限制

**接口随时可能失效。** 应用使用官方 CLI 所用的 client ID 和非公开用量接口。
Provider 收紧策略时，登录或额度查询会直接失效。这是这条实现路径的固有代价，
技术上无法消除。

**登录依赖本地回环端口。** OAuth 回调走 `http://localhost:<port>`，
Codex 先试 1455、失败再回退 1457，Claude Code 用 41999。端口被其他应用占用时登录会失败——
手机上没法查端口占用，遇到时先关掉后台应用重试，仍不行就重启手机。

**只读当前额度。** 没有历史曲线，没有用量趋势，没有跨设备同步。

---

## 故障排查

应用内的每种失败都有明确文案，下面是它们的含义和对策：

| 你看到 | 含义 | 怎么办 |
|---|---|---|
| 还没登录 X | 该 Provider 无凭据 | 点登录 |
| 登录已失效 | 凭据过期或被撤销 | 重新登录；此时显示的是旧数据 |
| 刷新已暂缓 | Provider 要求降频 | 等退避结束，旧数据仍保留 |
| 暂时无法连接 | 网络不可达 | 网络恢复后前台自动重试 |
| 额度数据无法识别 | 响应格式变了 | 多半是 Provider 改了接口，请提 Issue |
| 当前额度窗口暂不支持 | 返回了未知窗口类型 | 请提 Issue 并附上套餐类型 |
| 刚刷新过，1 分钟后可再试 | 触发手动节流 | 等一分钟 |

登录失败还有几种更具体的原因：

| 提示 | 原因 |
|---|---|
| Codex 登录端口 1455 和 1457 都被占用 | 本机有程序占着回环端口 |
| 无法打开系统浏览器 | 系统未配置默认浏览器 |
| X 登录超时，请重试 | 授权页停留过久 |
| X 登录交换凭据失败 | code 换 token 阶段失败 |
| 无法安全保存 X 登录凭据 | Keychain / Keystore 写入被拒 |
| 无法读取本机存储，请重启应用 | 安全存储初始化失败 |

---

## 开发

**技术栈**：Flutter 3.44.8 / Dart SDK `^3.12.2`。
运行时依赖只有四个：`http`、`crypto`、`flutter_secure_storage`、`shared_preferences`。

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test

flutter build apk --debug --target-platform android-arm64
flutter build ios --release --no-codesign
```

**目录**

| 路径 | 内容 |
|---|---|
| `lib/app/` | 刷新调度、退避、状态编排 |
| `lib/auth/` | OAuth + PKCE、回环回调服务 |
| `lib/providers/` | 接口请求与用量解析 |
| `lib/domain/` | 额度模型与状态语义 |
| `lib/ui/` | 主屏、设置页、主题 |
| `lib/q3/` | OAuth 回环连通性验证工具，仅在 Debug 构建的设置页中可见 |

**CI**：push `main` / PR 触发 `flutter analyze`、`flutter test`、iOS 无签名 Release 编译，
以及 Android **debug** APK 编译。推送与 `pubspec.yaml` 版本匹配的 `v*` tag 后，Release
流水线会重跑一遍分析与测试，再用正式签名密钥构建 **release** arm64 APK 并创建公开 Release。
详见 [GitHub 自动构建与发布](docs/GitHub自动构建与发布.md)。

**设计决策**

- [ADR-0001](docs/决策/ADR-0001-独立仓库与技术栈选型.md) — 为什么和桌面端分仓
- [ADR-0002](docs/决策/ADR-0002-Flutter移动端技术栈.md) — 为什么选 Flutter
- [移动端额度展示要求](docs/移动端额度展示要求.md) — 每条数据的来源和证据等级
- [OAuth 可行性验证](docs/OAuth可行性验证.md) · [真机验证专项计划](docs/S1-Q3真机验证专项计划.md) — iOS 侧剩余的验证任务
- [界面原型](docs/原型/额度主屏.html) — clone 后用浏览器打开（GitHub 上点开只会显示源码）

---

## 贡献

现阶段最有价值的贡献是**真机验证结果**，尤其是 **iOS 自签安装**的实际体验，以及
你的套餐类型、Provider 返回的窗口结构和任何解析失败的场景。提 Issue 时请务必**脱敏**——
不要粘贴 token、authorization code 或任何凭据片段。

代码改动请先跑 `flutter analyze` 和 `flutter test`。

---

## 相关项目

| | |
|---|---|
| [**CC Trace**](https://github.com/nanvon/cc-trace) | 桌面端 · macOS 菜单栏 / Windows 托盘 |
| **CC Trace Mobile**（本仓库） | 移动端 · iOS / Android |

两个独立应用，不是移植关系。共享同一套视觉语言和额度口径，代码结构各走各的。

---

## 免责声明

本项目不是 OpenAI 或 Anthropic 的官方产品，与两家公司无关，也未获得其认可或支持。
Codex、Claude 及相关名称归各自所有者。

## 许可证

[MIT](LICENSE)

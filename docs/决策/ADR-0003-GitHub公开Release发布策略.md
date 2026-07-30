# ADR-0003：GitHub 公开 Release 发布策略

## 状态

已接受（2026-07-30）

## 背景

移动端 Android Release workflow 原先使用 `--draft` 创建 GitHub Draft Release，只有仓库
维护者能看到，普通用户无法下载构建产物。Android APK 的正式签名、版本、ABI 和 SHA-256
验收已经由 workflow 完成，但 Draft 状态阻断了用户查看和下载。

## 决策

`v*` tag 对应的 Release workflow 在构建、签名和验收全部通过后，直接创建公开 Release，
不再传入 `--draft`。

## 原因

- 用户需要让普通账号直接看到并下载 Android APK；
- GitHub 的 Draft 可见性不适合作为当前交付入口；
- 构建验收与真实 Provider / OAuth / 双平台真机验证是不同层次，公开 Release 不宣称后者已经完成。

## 代价与边界

- 任何通过发布门禁的 APK 都会对公开仓库读者可见；
- 公开包仍可能包含尚未完成真机验证的实现假设；
- Android 正式 keystore 和四个 GitHub Secret 仍是 Release 的硬前提；
- iOS 继续只做无签名 CI 编译，不生成可分发 IPA。

## 后续

每次发布前仍需更新 `pubspec.yaml` 的 `versionName+versionCode`，等待对应的 CI / Release
workflow 完成，并检查公开 Release 中的 APK 与 SHA-256 文件。若真实验证结果要求暂停公开，
可恢复 `--draft` 并更新本 ADR。

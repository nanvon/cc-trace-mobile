# GitHub 自动构建与发布

## 1. 能力边界

仓库使用两个 GitHub Actions 工作流：

- `.github/workflows/ci.yml`：push `main`、Pull Request 或手动触发。
- `.github/workflows/release.yml`：推送 `v*` tag 时触发。

CI 会运行 Dart 静态分析、自动化测试、Android Debug 编译和 iOS 无签名 Release 编译。
Release 会再次执行版本校验、自动化测试与双平台编译门禁，并在全部通过后创建并公开
Release。

平台产物边界：

- Android：上传项目正式证书签名的 arm64 APK 和对应 SHA-256。
- iOS：只执行 `flutter build ios --release --no-codesign`，不上传 IPA。免费 Apple ID
  无法在 GitHub Hosted Runner 上形成可长期安装或公开分发的签名链，仍须在本机 Xcode
  中自签安装并接受 7 天重签。

iOS 无签名编译通过只能证明当前 Flutter / Swift 工程能在 CI 工具链中编译，不能替代
免费 Apple ID 真机安装、OAuth 回跳、Keychain 或双平台真机验证。

## 2. Android GitHub Actions Secrets

首次推送发布 tag 前，必须在 GitHub 仓库的
`Settings → Secrets and variables → Actions` 中配置以下 Repository secrets：

| Secret | 内容 |
|---|---|
| `ANDROID_RELEASE_KEYSTORE_BASE64` | 正式 JKS 文件的单行 Base64 |
| `ANDROID_RELEASE_STORE_PASSWORD` | keystore 密码 |
| `ANDROID_RELEASE_KEY_ALIAS` | 正式 key alias |
| `ANDROID_RELEASE_KEY_PASSWORD` | 正式 key 密码 |

这些值不得写入仓库、Actions 日志、Issue、PR 或 Release 说明。工作流只把 JKS 临时恢复到
GitHub Runner 的 `$RUNNER_TEMP`，Runner 销毁后不保留。

缺少任一 Secret 时，Release 工作流会明确失败；Android 构建不得回退到 debug key。构建后的
APK 仍会由 `scripts/verify_android_release.sh` 核对唯一 signer、仓库钉扎证书指纹、ABI、
版本号和 SHA-256。

## 3. 发布步骤

`pubspec.yaml` 是版本唯一来源：

```yaml
version: 0.1.0+2001
```

其中 `0.1.0` 是 `versionName`，`2001` 是 Android `versionCode`。每次发布必须先更新版本并
递增 `versionCode`，提交并推送到 `main`，等待 CI 通过，再创建完全匹配的 tag：

```bash
git tag v0.1.0
git push origin v0.1.0
```

`scripts/check_release_version.sh` 会拒绝 tag 与 `versionName` 不一致的发布。例如
`0.1.0+2001` 只接受 `v0.1.0`。

Release 工作流成功后会：

1. 确认 tag、`versionName` 和 `versionCode` 格式正确。
2. 运行静态分析、自动化测试与 iOS 无签名 Release 编译。
3. 使用正式 Android key 构建和验收 arm64 APK。
4. 创建并公开 Release。
5. 上传 `CC-Trace-Mobile_<版本>_Android-arm64.apk` 和 `.sha256`。

公开 Release 只证明构建、签名和上传门禁通过，不等于真实 Provider、OAuth 或双平台真机
验收完成；这些未完成项仍必须按真机验证计划执行。

## 4. 首次启用验收

工作流文件进入 `main` 后，先从 GitHub Actions 页面手动运行一次 CI。它成功只证明自动化
检查链路可用，不改变现有真机验证状态。

Android Secrets 配置完成后，每个 tag 发布需要确认：

- Release 已公开且 tag、版本和文件名正确；
- APK 文件名和版本正确；
- SHA-256 文件对应上传的 APK；
- Actions 日志没有 keystore、密码、token 或 authorization code；
- 下载 APK 后再次执行 `scripts/verify_android_release.sh <APK 路径>` 仍通过。

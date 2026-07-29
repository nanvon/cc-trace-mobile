# Android 正式签名与发布

## 1. 不可替代的签名身份

`com.nanvon.cctrace.mobile` 的 Release APK 只允许使用项目独立的
`cc-trace-mobile-release` key。应用一旦分发，后续更新必须继续使用同一把 key；丢失 key
或密码会失去原应用的升级能力。

仓库只保存正式证书的公开 SHA-256 指纹：

```text
android/release-signing-certificate.sha256
```

Keystore 与密码不进入仓库。当前开发机的默认位置为：

```text
~/.config/cc-trace-mobile/cc-trace-mobile-release.jks
~/.config/cc-trace-mobile/android-signing.properties
```

两个文件均应为 `0600`，上级目录应为 `0700`。也可以通过 Gradle 属性
`ccTraceSigningProperties` 或环境变量
`CC_TRACE_MOBILE_ANDROID_SIGNING_PROPERTIES` 指向其他配置文件。CI 可改用以下环境变量，
不必生成属性文件：

```text
CC_TRACE_MOBILE_ANDROID_STORE_FILE
CC_TRACE_MOBILE_ANDROID_STORE_PASSWORD
CC_TRACE_MOBILE_ANDROID_KEY_ALIAS
CC_TRACE_MOBILE_ANDROID_KEY_PASSWORD
```

Release 任务缺少正式签名配置时必须失败，不允许回退到 debug key。

## 2. 唯一版本来源

Flutter 与 Android 的正式版本统一取自 `pubspec.yaml`：

```yaml
version: 0.1.0+2001
```

- `0.1.0` 是 `versionName`。
- `2001` 是 Android `versionCode`。
- 每次正式发布必须递增 `versionCode`；`versionName` 按产品版本更新。
- 正式构建不得临时传 `--build-name` 或 `--build-number`，避免产物与仓库不一致。

仓库曾保留 `versionCode 2001` 的 arm64 split APK，而默认源仍是 `1`。原因是 Flutter
`--split-per-abi` 会按 `ABI 序号 × 1000 + pubspec build number` 重写最终 versionCode。
正式构建现不再使用该参数，并以 `2001` 为仓库基线；最终 APK 的 versionCode 因此严格等于
`pubspec.yaml`，也避免后续 APK 被 Android 判定为降级版本。

## 3. 构建与自动验收

在仓库根目录执行：

```bash
./scripts/build_android_release.sh
```

脚本固定构建只含 `arm64-v8a` 的单一 APK。Flutter 3.44.8 默认会重置
`defaultConfig.ndk.abiFilters`，因此脚本同时传入 `-P disable-abi-filtering=true`，由
Release 构建类型中的 arm64 filter 接管。不要遗漏或单独使用其中一项。

构建完成后自动检查：

- APK 签名有效且只有一个 signer；
- 证书 SHA-256 与仓库钉扎值一致；
- ABI 只有 `arm64-v8a`；
- `versionName` / `versionCode` 与 `pubspec.yaml` 一致；
- 生成 APK 自身的 SHA-256 文件。

产物位于：

```text
build/app/outputs/flutter-apk/app-release.apk
build/app/outputs/flutter-apk/app-release.apk.sha256
```

只复核已有 APK 时执行：

```bash
./scripts/verify_android_release.sh
```

## 4. 备份与恢复

正式 key 必须使用加密恢复包备份至少两份，并存放在相互独立、访问受控的位置。恢复包、
解密口令、具体备份位置和账户或钥匙串标识不得写入公开仓库。

生成或恢复后必须逐份校验完整性，将 keystore 目录权限设为 `0700`、文件权限设为 `0600`，
再运行验收脚本确认公开证书指纹未变化。

具体生成、存放与恢复步骤只记录在 Git 忽略的
`docs/private/Android签名恢复.md`，不复制到 issue、PR、Release 说明或公开日志。

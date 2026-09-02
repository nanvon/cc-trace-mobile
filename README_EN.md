<p align="center">
  <img src="ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png" width="128" alt="CC Trace Mobile Icon">
</p>

<h1 align="center">CC Trace Mobile</h1>

<p align="center">
  <b>Mobile Quota Monitor for Codex and Claude Code on iOS & Android</b><br>
  Track AI quotas, reset countdowns, and extra usage on the go without returning to your desktop.
</p>

<p align="center">
  <img alt="iOS" src="https://img.shields.io/badge/iOS-13%2B-000000?logo=apple&logoColor=white">
  <img alt="Android" src="https://img.shields.io/badge/Android-arm64-3DDC84?logo=android&logoColor=white">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white">
  <a href="https://github.com/nanvon/cc-trace-mobile/releases/latest"><img alt="Latest Release" src="https://img.shields.io/github/v/release/nanvon/cc-trace-mobile?color=brightgreen"></a>
  <img alt="License" src="https://img.shields.io/badge/license-MIT-orange">
</p>

<p align="center">
  <a href="https://github.com/nanvon/cc-trace-mobile/releases/latest">Download</a> ·
  <a href="#-features">Features</a> ·
  <a href="#-installation">Installation</a> ·
  <a href="#-security--privacy">Security</a> ·
  <a href="#-building-from-source">Build from Source</a> ·
  <a href="https://github.com/nanvon/cc-trace-mobile/issues">Feedback</a> ·
  <a href="README.md">简体中文</a>
</p>

---

## ✨ Features

### ⚡ Dual-Engine Quota Insights
* **Multi-Window Tracking** — Pulls 5-hour session windows and weekly quota windows for both Codex and Claude Code, displaying exact remaining percentages and reset countdowns.
* **4-Tier Status Progress Bars** — Progress bars are color-coded based on remaining quota (>50% green, 20%~50% yellow, <20% orange, 0% red) for instant health evaluation.
* **Bonus Credits & Extra Spend** — Automatically detects and independently presents Codex Reset Credits bonus points, along with Claude Code's monthly extra spend, budget cap, and consumption ratio.
* **Model-Specific Quotas** — Fully parses dedicated model-tier weekly quota windows (such as Opus / Sonnet / Haiku quotas) for Claude Code high-tier subscriptions.

### 🔐 Native Auth & Local Storage
* **Standard OAuth 2.0 PKCE** — Launches the external system browser to log in on official provider domains; passwords are never entered or stored within the app.
* **Secure Loopback Callbacks** — Built-in local HTTP loopback server receives redirect callbacks with automatic port fallback (Codex 1455 / 1457, Claude 41999 / 41998 / 41997).
* **Hardware-Backed Secure Storage** — Tokens are strictly stored in iOS Keychain (unlocked device only) and Android Keystore (encrypted namespace `cc_trace_mobile`).
* **Decoupled Multi-Account Sign-In** — Codex and Claude Code operate independently; you can sign in to just one provider, and signing out immediately wipes the associated credentials and quota cache.

### 🍃 Restrained & Battery-Friendly
* **Foreground-Only Operation** — Automatic refreshes only run when active in the foreground, with configurable intervals (15 / 30 / 60 minutes, default 30 min); zero background polling, zero push notifications.
* **Request Throttling & Exponential Backoff** — Manual pull-to-refresh enforces a 1-minute throttle; automatically follows graduated exponential backoff upon encountering HTTP 429 rate limits.
* **3-Dimensional State Contract** — Adheres to the "Activity / Snapshot Freshness / Error Kind" model; retains the last valid snapshot with a timestamp when offline or on error, never masquerading stale data as fresh.
* **Android Keep-Alive & Diagnostics** — Employs a short-lived foreground service during login to prevent loopback server termination when switching browsers, paired with an in-app browser selector and diagnostic logs.

### 🎨 Modern Design Guidelines
* **HeroUI Visual System** — Inherits the Slate cool-gray styling and design tokens from the desktop suite, delivering a clean, modern aesthetic with minimal visual noise.
* **Adaptive Theme Support** — Supports System, Light, and Dark appearance preferences, with native edge-to-edge layout support on Android 15 and above.

---

## 📦 Installation

> **Platforms**: iOS 13.0+ · Android (arm64-v8a)<br>
> **Prerequisites**: An active paid subscription for Codex or Claude Code (at least one signed in).

### Android (Recommended)
Download the latest `CC-Trace-Mobile_<version>_Android-arm64.apk` directly from the [Releases page](https://github.com/nanvon/cc-trace-mobile/releases/latest):
- Every release APK is signed with the official release key and ships with a matching `.sha256` checksum for verification.
- Allow "Install unknown apps" in system settings when installing for the first time.

### iOS (Self-Signing)
Following the project's security and distribution constraints, this project does not subscribe to Apple Developer Program and **does not offer App Store, TestFlight, or pre-signed IPA downloads**. Installing on physical devices is supported via Xcode self-signing with a **free Apple ID** (requires re-signing every 7 days due to Apple restrictions):

```bash
# 1. Clone the repository and install dependencies
git clone https://github.com/nanvon/cc-trace-mobile.git
cd cc-trace-mobile
flutter pub get --enforce-lockfile

# 2. Connect your iOS device and run in Release mode (configure your personal Apple ID team in Xcode)
flutter run --release
```

> [!NOTE]
> **Device Verification Status**
> - **Android**: Formally signed arm64 APK builds and all 59 unit/integration tests are enforced via CI release gates.
> - **iOS**: GitHub Actions continuously verifies unsigned Release compilation (`flutter build ios --release --no-codesign`). Physical device testing requires local Xcode self-signing.

---

## 🔒 Security & Privacy

CC Trace Mobile adheres strictly to a **local-first, zero-intermediary** architecture with no proprietary servers:

### Credential Storage & Security Model

| Service / Component | Credential Storage Location | Permissions | Operational Mechanism & Safeguards |
| :--- | :--- | :---: | :--- |
| **Codex** | iOS Keychain / Android Keystore (`cc_trace_mobile`) | Read / Write | Standard OAuth 2.0 PKCE flow; local loopback ports (1455 / 1457) receive auth codes; calls official endpoints only, automatic token refresh before expiration |
| **Claude Code** | iOS Keychain / Android Keystore (`cc_trace_mobile`) | Read / Write | Standard OAuth 2.0 PKCE flow; local loopback ports (41999 sequence) receive auth codes; calls official endpoints only |
| **Quota Cache** | Local SharedPreferences | Read / Write | Persists only the last successful quota snapshot and timestamp for offline viewing; wiped completely upon sign-out alongside credentials |

### Zero Telemetry & Privacy Commitments
* **No Intermediary Server**: The application contains no custom backend. All network requests communicate directly with official OpenAI / Anthropic endpoints without third-party proxies.
* **Zero Telemetry or Tracking**: Contains no analytics SDKs, crash reporters, or behavioral trackers. No device identifiers or usage habits are collected or transmitted.
* **Memory & Log Redaction**: Access tokens, refresh tokens, and authorization codes are strictly redacted across the codebase; they are never printed to console logs, crash files, or UI views.
* **Complete Clean Slate**: Signing out in Settings immediately deletes all associated tokens from the Keychain / Keystore and flushes local storage caches.

> [!TIP]
> Authentication and quota queries use the official CLI client IDs and API endpoints. To fully inspect the networking and storage implementation, feel free to [build from source](#-building-from-source).

---

## 🔧 Building from Source

Built with Flutter and Dart, maintaining minimal runtime dependencies.

### Prerequisites
- **Flutter SDK**: 3.24+ (Dart ^3.12.2)
- **Android Toolchain**: JDK 17 + Android SDK (API 34+)
- **iOS Toolchain**: macOS + Xcode 15+

### Daily Development
```bash
# Check dependencies and install
flutter pub get --enforce-lockfile

# Run static analysis and automated test suite
flutter analyze
flutter test

# Start local debugging
flutter run
```

### Production Build Commands
```bash
# Build signed Android arm64 APK
flutter build apk --release --target-platform android-arm64

# Build unsigned iOS release artifact
flutter build ios --release --no-codesign
```

> [!TIP]
> For details on Android signing key configuration, certificate pinning, and GitHub Actions release automation, refer to [GitHub Automated Build & Release](docs/GitHub自动构建与发布.md) and [Android Release Signing](docs/Android正式签名与发布.md).

---

## 🔗 Related Projects

A family of companion tools sharing unified quota metrics, state contracts, and 4-tier health colors:

| Project | Platform Form | Tech Stack | Highlights |
| :--- | :--- | :--- | :--- |
| [**cc-bar**](https://github.com/nanvon/cc-bar) | Native macOS Menu Bar Tool | Swift / SwiftUI | Extremely lightweight, direct menu bar percentage display, desktop HUD widget, and local session analytics |
| [**CC Trace**](https://github.com/nanvon/cc-trace) | Desktop Client (macOS / Windows) | Tauri / Web (HeroUI) | Cross-platform tray and popover HUD with multi-engine quota insights |
| **CC Trace Mobile** (this repo) | Mobile Companion (iOS / Android) | Flutter / Dart | Pocket quota monitor, direct official OAuth, offline snapshot display, restrained low power usage |

> [!NOTE]
> All three applications run independently. Data and settings are strictly stored on local devices without synchronization servers.

---

## 📢 Disclaimer

This project is an independent open-source tool and is not affiliated with, endorsed by, or sponsored by OpenAI or Anthropic. Codex, Claude, and related trademarks belong to their respective owners.

---

## 📄 License

This project is open-sourced under the [MIT](LICENSE) License.

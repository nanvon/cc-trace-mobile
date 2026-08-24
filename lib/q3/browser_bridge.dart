import 'dart:async';

import 'package:flutter/services.dart';

enum OAuthBrowserEventType { cancelled, returned, failed }

class OAuthBrowserEvent {
  const OAuthBrowserEvent(this.type, {this.category});

  final OAuthBrowserEventType type;
  final String? category;
}

/// 设备上可用于打开授权页的浏览器。
///
/// 由用户在登录时挑选，不由系统「默认浏览器」代劳：默认浏览器不一定支持
/// Custom Tabs，也不一定是用户登录过 Provider 的那个。
class BrowserChoice {
  const BrowserChoice({
    required this.packageName,
    required this.label,
    required this.supportsCustomTabs,
    required this.isDefault,
  });

  final String packageName;
  final String label;
  final bool supportsCustomTabs;
  final bool isDefault;

  static BrowserChoice? fromPlatform(Object? value) {
    if (value is! Map) {
      return null;
    }
    final packageName = value['packageName'];
    final label = value['label'];
    if (packageName is! String || packageName.isEmpty) {
      return null;
    }
    return BrowserChoice(
      packageName: packageName,
      label: label is String && label.isNotEmpty ? label : packageName,
      supportsCustomTabs: value['supportsCustomTabs'] == true,
      isDefault: value['isDefault'] == true,
    );
  }

  @override
  String toString() => 'BrowserChoice($packageName)';
}

abstract interface class BrowserLauncher {
  Stream<OAuthBrowserEvent> get events;

  /// 可用浏览器列表。平台不支持选择（iOS）时返回空列表。
  Future<List<BrowserChoice>> listBrowsers();

  /// [packageName] 为空时由平台自行决定（iOS 会话流程 / Android 兜底）。
  Future<void> open(Uri authorizeUri, {String? packageName});

  Future<void> close();
  Future<void> release();
  Future<void> dispose();
}

class OAuthBrowserBridge implements BrowserLauncher {
  OAuthBrowserBridge() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const MethodChannel _channel = MethodChannel(
    'com.nanvon.cctrace.mobile/oauth_browser',
  );

  final StreamController<OAuthBrowserEvent> _events =
      StreamController<OAuthBrowserEvent>.broadcast(sync: true);

  @override
  Stream<OAuthBrowserEvent> get events => _events.stream;

  @override
  Future<List<BrowserChoice>> listBrowsers() async {
    final List<Object?>? raw;
    try {
      raw = await _channel.invokeListMethod<Object?>('listBrowsers');
    } on Object {
      // 平台未实现浏览器选择（iOS）：交回平台自身的会话流程。
      return const [];
    }
    if (raw == null) {
      return const [];
    }
    final choices = <BrowserChoice>[];
    for (final item in raw) {
      final choice = BrowserChoice.fromPlatform(item);
      if (choice != null) {
        choices.add(choice);
      }
    }
    return choices;
  }

  @override
  Future<void> open(Uri authorizeUri, {String? packageName}) async {
    await _channel.invokeMethod<void>('open', <String, String?>{
      'url': authorizeUri.toString(),
      'package': packageName,
    });
  }

  @override
  Future<void> close() async {
    await _channel.invokeMethod<void>('close');
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (_events.isClosed) {
      return;
    }

    switch (call.method) {
      case 'browserCancelled':
        _events.add(const OAuthBrowserEvent(OAuthBrowserEventType.cancelled));
        break;
      case 'browserReturned':
        _events.add(const OAuthBrowserEvent(OAuthBrowserEventType.returned));
        break;
      case 'browserFailed':
        final arguments = call.arguments;
        final category = arguments is Map
            ? arguments['category'] as String?
            : null;
        _events.add(
          OAuthBrowserEvent(OAuthBrowserEventType.failed, category: category),
        );
        break;
    }
  }

  /// 终态后的平台资源释放：Android 解绑 Custom Tabs 服务，iOS 关闭会话。
  ///
  /// 仅供 OAuth 进入终态（成功 / 取消 / 超时 / 失败）后调用；best-effort，
  /// 平台清理失败绝不能覆盖 OAuth 原始结果。
  @override
  Future<void> release() async {
    try {
      await _channel.invokeMethod<void>('release');
    } on Object {
      // Best-effort cleanup; platform failure must not replace the OAuth result.
    }
  }

  @override
  Future<void> dispose() async {
    await release();
    _channel.setMethodCallHandler(null);
    await _events.close();
  }
}

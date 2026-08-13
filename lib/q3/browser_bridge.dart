import 'dart:async';

import 'package:flutter/services.dart';

enum OAuthBrowserEventType { cancelled, returned, failed }

class OAuthBrowserEvent {
  const OAuthBrowserEvent(this.type, {this.category});

  final OAuthBrowserEventType type;
  final String? category;
}

abstract interface class BrowserLauncher {
  Stream<OAuthBrowserEvent> get events;
  Future<void> open(Uri authorizeUri);
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
  Future<void> open(Uri authorizeUri) async {
    await _channel.invokeMethod<void>('open', <String, String>{
      'url': authorizeUri.toString(),
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

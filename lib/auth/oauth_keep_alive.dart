import 'package:flutter/services.dart';

/// 登录期间的进程保活。
///
/// Android 上授权页在浏览器里打开，本应用退到后台；系统的缓存进程冻结会让
/// loopback server 无人 accept，浏览器就永远停在加载中。登录开始时拉起一个
/// 短时前台服务，终态立即停止。iOS 不需要（`ASWebAuthenticationSession`
/// 期间应用仍在前台），平台未实现时静默降级。
abstract interface class SignInKeepAlive {
  Future<bool> start();
  Future<void> stop();
}

class PlatformSignInKeepAlive implements SignInKeepAlive {
  const PlatformSignInKeepAlive();

  static const MethodChannel _channel = MethodChannel(
    'com.nanvon.cctrace.mobile/oauth_keep_alive',
  );

  @override
  Future<bool> start() async {
    try {
      final started = await _channel.invokeMethod<bool>('start');
      return started ?? false;
    } on Object {
      // 保活是尽力而为：拉不起来也不能挡住登录本身。
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on Object {
      // 同上：停不掉也不能覆盖 OAuth 的原始结果。
    }
  }
}

class NoopSignInKeepAlive implements SignInKeepAlive {
  const NoopSignInKeepAlive();

  @override
  Future<bool> start() async => false;

  @override
  Future<void> stop() async {}
}

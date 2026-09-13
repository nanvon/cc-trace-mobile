import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_diagnostics.dart';

/// 把诊断日志接到全局异常钩子和持久化上，并记下本次启动的运行环境。
///
/// 必须在 `runApp` 之前调用：启动阶段的异常也要落进日志，而那时还没有任何控制器。
void installDiagnostics(AppDiagnostics diagnostics, DiagnosticsStore store) {
  // 保留原有处理器：控制台输出在开发时仍然要有，这里只是搭一条便车。
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    diagnostics.recordError('error.widget', details.exception, details.stack);
    previousOnError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    diagnostics.recordError('error.async', error, stack);
    // false 表示没有就地处理完，继续交给框架的默认行为。
    return false;
  };

  diagnostics.newSection('app.start', {
    'build': _buildMode,
    'platform': Platform.operatingSystem,
    'os': Platform.operatingSystemVersion,
  });
  unawaited(diagnostics.attach(store));
  // 版本号要过一次平台通道，不能挡住首帧；它紧跟在 app.start 后面单独一行。
  unawaited(_recordVersion(diagnostics));
}

Future<void> _recordVersion(AppDiagnostics diagnostics) async {
  try {
    final info = await PackageInfo.fromPlatform();
    diagnostics.record('app.version', {
      'name': info.version,
      'code': info.buildNumber,
    });
  } on Object {
    // 读不到就照实说，别让这一行缺失得不明不白。
    diagnostics.record('app.version', {'name': 'unknown'});
  }
}

String get _buildMode {
  if (kReleaseMode) {
    return 'release';
  }
  return kProfileMode ? 'profile' : 'debug';
}

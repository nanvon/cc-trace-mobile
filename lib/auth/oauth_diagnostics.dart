import 'package:flutter/foundation.dart';

/// 登录诊断日志。
///
/// 只记录事件名与判定结果（布尔、计数、包名、枚举名）。**任何情况下都不得写入
/// authorization code、token、账号标识或回调 query 的原始内容**——这份日志的用途
/// 就是让用户可以整份复制出来交给开发者。
class OAuthDiagnostics extends ChangeNotifier {
  OAuthDiagnostics({DateTime Function()? now, this.capacity = 160})
    : _now = now ?? DateTime.now;

  /// 应用全局实例：登录链路横跨 coordinator / callback server / 平台桥，
  /// 用单例比逐层传参更贴合它「事后取证」的定位。
  static final OAuthDiagnostics instance = OAuthDiagnostics();

  final DateTime Function() _now;
  final int capacity;
  final List<String> _entries = [];

  List<String> get entries => List.unmodifiable(_entries);
  bool get isEmpty => _entries.isEmpty;

  void record(String event, [Map<String, Object?> fields = const {}]) {
    final time = _now();
    final stamp =
        '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';
    final detail = fields.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    _entries.add(detail.isEmpty ? '$stamp  $event' : '$stamp  $event  $detail');
    if (_entries.length > capacity) {
      _entries.removeRange(0, _entries.length - capacity);
    }
    notifyListeners();
  }

  /// 开始一轮登录：保留上一轮记录，只插入分隔，方便对比连续两次尝试。
  void startSession(String provider) {
    if (_entries.isNotEmpty) {
      _entries.add('');
    }
    record('signIn.start', {'provider': provider});
  }

  String export() => _entries.join('\n');

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

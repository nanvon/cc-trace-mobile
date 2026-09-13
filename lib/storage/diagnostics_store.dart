import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/app_diagnostics.dart';

/// 诊断日志落盘。
///
/// 存的是脱敏后的事件行，本身不含凭据，所以不需要 secure storage；用普通偏好
/// 存储换来的是「应用被杀之后记录还在」，而崩溃恰恰是最需要日志的那一类问题。
class SharedPreferencesDiagnosticsStore implements DiagnosticsStore {
  SharedPreferencesDiagnosticsStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'diagnostics.v1';

  final SharedPreferencesAsync _preferences;

  @override
  Future<List<String>> read() async {
    final raw = await _preferences.getString(_key);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    return raw.split('\n');
  }

  @override
  Future<void> write(List<String> entries) {
    if (entries.isEmpty) {
      return _preferences.remove(_key);
    }
    return _preferences.setString(_key, entries.join('\n'));
  }

  @override
  Future<void> clear() => _preferences.remove(_key);
}

class MemoryDiagnosticsStore implements DiagnosticsStore {
  List<String> entries = [];

  @override
  Future<List<String>> read() async => List.of(entries);

  @override
  Future<void> write(List<String> value) async {
    entries = List.of(value);
  }

  @override
  Future<void> clear() async {
    entries = [];
  }
}

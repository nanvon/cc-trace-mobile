import 'dart:async';

import 'package:flutter/foundation.dart';

/// 诊断日志的持久化出口。
///
/// 单独于 `LocalStore`：日志要在 `AppController` 之前就能落盘（启动异常、
/// bootstrap 失败都发生在那之前），也不该跟着用量缓存一起被清。
abstract interface class DiagnosticsStore {
  Future<List<String>> read();
  Future<void> write(List<String> entries);
  Future<void> clear();
}

/// 日志里的一行。
///
/// 事件行带上它的原始内容（[payload]），这样反复出现的同一件事能被认出来、
/// 折叠成计数。日期分隔、空行和上次运行载入的历史都是 [_Line.plain]，只有文本。
class _Line {
  _Line.plain(String text) : _text = text, payload = null, stamp = '';

  _Line.event(this.payload, this.stamp) : _text = null, _lastStamp = stamp;

  final String? _text;
  final String? payload;
  final String stamp;
  String? _lastStamp;
  int repeats = 1;

  bool get isFoldable => payload != null;

  void fold(String at) {
    repeats++;
    _lastStamp = at;
  }

  String render() {
    if (payload == null) {
      return _text!;
    }
    if (repeats == 1) {
      return '$stamp  $payload';
    }
    return '$stamp  $payload  ×$repeats 至 $_lastStamp';
  }

  /// 体积估算，用于总量裁剪。避免每次裁剪都把整份日志重新渲染一遍。
  int get length =>
      (_text ?? payload)!.length +
      (payload == null ? 0 : stamp.length + 2) +
      (repeats > 1 ? 16 : 0);
}

/// 应用诊断日志。
///
/// 只记录事件名与判定结果（布尔、计数、枚举名、HTTP 状态码、异常类型名）。
/// **任何情况下都不得写入 access token、refresh token、authorization code、
/// 邮箱、账号标识、回调 query 或响应体原文**——这份日志的用途就是让用户整份
/// 复制出来交给开发者，它必须在「随手发给陌生人」这个前提下依然安全。
class AppDiagnostics extends ChangeNotifier {
  AppDiagnostics({
    DateTime Function()? now,
    this.capacity = 400,
    this.flushDelay = const Duration(seconds: 2),
  }) : _now = now ?? DateTime.now;

  /// 应用全局实例：日志要横跨登录链路、刷新链路和全局异常钩子，其中异常钩子
  /// 装在 `main` 里、早于任何控制器存在，用单例比逐层传参更贴合它的定位。
  static final AppDiagnostics instance = AppDiagnostics();

  /// 单条记录的字符上限：异常类型名和响应字段都可能异常长，截断后仍可读，
  /// 但不会让一条记录挤掉整段历史。
  static const _maxEntryLength = 240;

  /// 整份日志的字符上限。[capacity] 只管条数，管不住每条有多长；这条兜住
  /// 落盘体积，免得偏好存储里躺着一个几百 KB、每次刷盘都要整体重写的值。
  static const _maxTotalLength = 64 * 1024;

  /// 折叠回看多少行。
  ///
  /// 一次刷新失败会连着记好几条**不同**的事件（两个 Provider 各自的
  /// `http.unreachable` 加 `refresh.failed`），只比对紧邻的上一条，这种交替
  /// 重复一条都折不掉——断网一天就能把整个缓冲区填满，把真正有用的历史顶出去。
  static const _foldWindow = 8;

  final DateTime Function() _now;
  final int capacity;
  final Duration flushDelay;
  final List<_Line> _lines = [];
  DiagnosticsStore? _store;
  Future<void>? _restoring;
  Timer? _flushTimer;
  String? _lastDateMark;

  List<String> get entries =>
      List.unmodifiable(_lines.map((line) => line.render()));
  bool get isEmpty => _lines.isEmpty;

  /// 接上持久化，并载入上次运行留下的记录。多次调用只会载入一次。
  Future<void> attach(DiagnosticsStore store) {
    _store = store;
    return _restoring ??= _restore(store);
  }

  Future<void> _restore(DiagnosticsStore store) async {
    try {
      final saved = await store.read();
      if (saved.isEmpty) {
        return;
      }
      // 载入发生在启动早期，但那之前通常已经记下了几条；历史排在它们前面。
      // 历史只读：它属于上一次运行，不参与这一次的折叠。
      _lines.insertAll(0, saved.map(_Line.plain));
      _trim();
      notifyListeners();
    } on Object {
      // 读盘失败一律当作没有历史：日志读不出来不该拦住启动。
    }
  }

  void record(String event, [Map<String, Object?> fields = const {}]) {
    _record(event, fields);
  }

  /// 记录一个异常。
  ///
  /// 只写异常的**类型名**，不写 `toString()`：异常消息可能捎带请求体、URL 或
  /// 响应片段，那正是这份日志不能有的东西。定位靠类型名加调用栈里第一条属于
  /// 本应用的帧。
  void recordError(String event, Object error, StackTrace? stack) {
    final folded = _record(event, {
      'type': error.runtimeType.toString(),
      'at': _topAppFrame(stack),
    });
    // 异常之后进程可能就没了，第一条不等节流。但同一个异常反复抛（每帧一次的
    // build 错误就是这样）只会折叠计数，那时再每次都写盘就成了自造的 I/O 风暴。
    if (!folded) {
      unawaited(flush());
    }
  }

  /// 开始新的一段：保留之前的记录，只插入空行分隔，方便对比连续两次尝试。
  void newSection(String event, [Map<String, Object?> fields = const {}]) {
    if (_lines.isNotEmpty) {
      _lines.add(_Line.plain(''));
    }
    record(event, fields);
  }

  /// 开始一轮登录。
  void startSession(String provider) {
    newSection('signIn.start', {'provider': provider});
  }

  String export() => entries.join('\n');

  void clear() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _lines.clear();
    _lastDateMark = null;
    notifyListeners();
    unawaited(_store?.clear());
  }

  /// 立刻落盘。退到后台和记录异常时调用，别的时候交给节流。
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    final store = _store;
    if (store == null) {
      return;
    }
    try {
      // 历史还没读回来就写，会把上次运行的记录覆盖成这次的零星几条。
      await _restoring;
      await store.write(entries);
    } on Object {
      // 落盘失败不影响运行；下一次还会再试。
    }
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    super.dispose();
  }

  /// 返回这一条是否被折叠进了已有的记录。
  bool _record(String event, Map<String, Object?> fields) {
    final payload = _clip(_compose(event, fields));
    final time = _now();
    final stamp =
        '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}';

    // 跨天不折叠：否则日期分隔行永远插不进去，一条 ×288 会横跨两天而看不出来。
    final today = _dateMark(time);
    final existing = today == _lastDateMark ? _foldTarget(payload) : null;
    if (existing != null) {
      existing.fold(stamp);
      notifyListeners();
      _scheduleFlush();
      return true;
    }

    _markDate(today);
    _lines.add(_Line.event(payload, stamp));
    _trim();
    notifyListeners();
    _scheduleFlush();
    return false;
  }

  /// 最近 [_foldWindow] 行里内容相同的那一条。
  ///
  /// 扫到空行或日期行就停：不跨登录会话、不跨天折叠，那会让计数横跨两段互不
  /// 相干的上下文。
  _Line? _foldTarget(String payload) {
    final floor = _lines.length - _foldWindow;
    for (var i = _lines.length - 1; i >= 0 && i >= floor; i--) {
      final line = _lines[i];
      if (!line.isFoldable) {
        return null;
      }
      if (line.payload == payload) {
        return line;
      }
    }
    return null;
  }

  String _compose(String event, Map<String, Object?> fields) {
    final detail = fields.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    return detail.isEmpty ? event : '$event  $detail';
  }

  String _clip(String entry) {
    // 换行会在落盘往返（按行 join / split）时把一条拆成两条，这里就地压平。
    final flat = entry.contains('\n')
        ? entry.replaceAll(RegExp(r'\s*\n\s*'), ' ')
        : entry;
    return flat.length > _maxEntryLength
        ? '${flat.substring(0, _maxEntryLength)}…'
        : flat;
  }

  /// 跨天的记录会被一起复制出来，只有 `HH:MM:SS` 就分不清是哪天的了。
  /// 日期只在变化时单独占一行，不挤进每一条。
  void _markDate(String mark) {
    if (mark == _lastDateMark) {
      return;
    }
    _lastDateMark = mark;
    _lines.add(_Line.plain('—— $mark ——'));
  }

  String _dateMark(DateTime time) =>
      '${time.year}-${_two(time.month)}-${_two(time.day)}';

  void _trim() {
    if (_lines.length > capacity) {
      _lines.removeRange(0, _lines.length - capacity);
    }
    var total = _lines.fold<int>(0, (sum, line) => sum + line.length + 1);
    if (total <= _maxTotalLength) {
      return;
    }
    var drop = 0;
    while (total > _maxTotalLength && drop < _lines.length - 1) {
      total -= _lines[drop].length + 1;
      drop++;
    }
    _lines.removeRange(0, drop);
  }

  void _scheduleFlush() {
    if (_store == null || _flushTimer != null) {
      return;
    }
    _flushTimer = Timer(flushDelay, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  /// 调用栈里第一条属于本应用的帧，形如 `app/app_controller.dart:120`。
  ///
  /// 只认 `package:cc_trace_mobile/`：框架和三方库的帧对定位没有帮助，而完整
  /// 栈文本里可能出现闭包捕获的参数。开启符号混淆后取不到，返回 null。
  static String? _topAppFrame(StackTrace? stack) {
    if (stack == null) {
      return null;
    }
    try {
      final match = _framePattern.firstMatch(stack.toString());
      if (match == null) {
        return null;
      }
      return '${match.group(1)}:${match.group(2)}';
    } on Object {
      // 自定义 StackTrace 的 toString 也可能抛；记日志本身不该再引发异常。
      return null;
    }
  }

  static final _framePattern = RegExp(
    r'package:cc_trace_mobile/([\w/]+\.dart):(\d+)',
  );

  static String _two(int value) => value.toString().padLeft(2, '0');
}
